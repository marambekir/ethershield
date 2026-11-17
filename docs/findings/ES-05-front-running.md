# ES-05 — Front-running / attaque sandwich sur `VulnerableAMM`

| Champ | Valeur |
|---|---|
| Sévérité | **Élevée** (Impact élevé sur chaque utilisateur × Probabilité élevée : des bots MEV surveillent le mempool en permanence) |
| Statut | Atténué dans `SecureAMM` (protection contre la perte, pas contre l'observation) |
| Fichier | `src/vulnerable/VulnerableAMM.sol` L39-52 |
| Détecteur Slither | **Aucun** sur la faille principale (faux négatif) |
| SWC | SWC-114 (Transaction Order Dependence) |

## Description
`swap(tokenIn, amountIn)` exécute l'échange au prix du **moment de l'exécution**, sans
montant minimum garanti ni date limite. Une transaction en attente dans le mempool est
publique : un attaquant peut l'encadrer.
1. **Front-run** : l'attaquant achète le même actif avec un gas price plus élevé → le prix monte.
2. **Victime** : son swap s'exécute au prix dégradé, sans aucune limite.
3. **Back-run** : l'attaquant revend juste après → il empoche la différence.

## Cause racine
Le résultat dépend de l'**ordre des transactions dans le bloc**, que l'utilisateur ne
contrôle pas, et le contrat n'offre aucun moyen d'exprimer un prix acceptable.

## Impact (pool 100 A / 100 B, alice échange 10 A)
| | Sans attaque | Avec sandwich |
|---|---|---|
| alice reçoit | 9,07 B | **5,48 B (−40 %)** |
| eve | — | **+4,03 A de profit** (30 → 34,03) |

## Preuves
**1. Test Forge** : `forge test --match-path test/exploits/FrontRunning.t.sol -vv`
```
Alice attendait   : 9066108938801491315
Alice a recu      : 5482992009014852787
Profit d'eve (A)  : 4025502491565627756
```
**2. Démo réelle sur Anvil** (minage manuel, tri par gas price) :
```bash
anvil                                  # terminal 2
forge script script/DeployFrontRunning.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
bash script/demo-sandwich.sh <AMM> <TokenA> <TokenB>
```
Les 3 transactions sont envoyées dans l'ordre alice → eve → eve, mais le bloc les
exécute dans l'ordre **eve (50 gwei) → alice (3 gwei) → eve (2 gwei)**.

## Correctif
1. **`minAmountOut`** : l'utilisateur fixe un plancher (devis − tolérance, ici 0,5 %).
   Si le prix a été manipulé, la transaction **revert** au lieu d'exécuter à perte.
2. **`deadline`** : empêche qu'une transaction soit retenue puis exécutée plus tard.
3. **`SafeERC20`** + mise à jour des réserves **avant** les transferts (CEI).

Effet sur l'attaquant : sans victime à exploiter, le front-run + back-run lui **coûte**
2 × 0,3 % de frais. L'attaque devient non rentable.

## Validation
| Test | Résultat |
|---|---|
| `test_NormalSwapWithinSlippage` | ✅ |
| `test_Regression_SandwichReverts` | ✅ revert `SlippageExceeded`, alice garde ses 10 A, eve perd de l'argent |
| `test_Regression_ExpiredTransaction` | ✅ revert `Expired` |
| `testFuzz_VictimNeverBelowMinOut` (front-run de 0,001 à 1000 A) | ✅ alice reçoit ≥ minOut, ou ne perd rien |
| `invariant_KNeverDecreases` (x·y ne diminue jamais) | ✅ |
| `invariant_ReservesMatchBalances` | ✅ |

## Analyse Slither — triage
| Finding | Contrat | Verdict |
|---|---|---|
| *(aucun détecteur)* sur l'absence de slippage / deadline | Vulnerable | **Faux négatif** : dépendance à l'ordre des transactions, invisible pour l'analyse statique |
| `unchecked-transfer` | Vulnerable | **Vrai positif secondaire** : un token qui renvoie `false` au lieu de revert fausserait les réserves. Corrigé par `SafeERC20` |
| `reentrancy-no-eth` | Vulnerable | **Vrai positif secondaire** : exploitable avec un token à hooks (ERC-777). Corrigé : réserves mises à jour avant les transferts |
| `timestamp` (`block.timestamp > deadline`) | Secure | **Accepté** : décalage possible de quelques secondes seulement, sans impact sur une deadline |

## Limites résiduelles
- La protection est **partielle** : l'attaquant peut encore extraire jusqu'à la tolérance
  choisie (0,5 %). Une tolérance trop large laisse place au sandwich.
- La transaction reste **visible** dans le mempool. Atténuations complémentaires :
  mempool privé (ex. Flashbots Protect), schéma **commit-reveal**, enchères par lots
  (batch auctions), ou oracle de prix (TWAP) pour les mécanismes sensibles.
- `minAmountOut` est calculé hors-chaîne : une interface compromise peut le mettre à 0.
