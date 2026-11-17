# ES-01 — Réentrance dans `VulnerableVault.withdraw()`

| Champ | Valeur |
|---|---|
| Sévérité | **Critique** (Impact élevé × Probabilité élevée) |
| Statut | Corrigé dans `SecureVault` |
| Fichier | `src/vulnerable/VulnerableVault.sol` L20-33 |
| Détecteur Slither | `reentrancy-eth` (High) |
| SWC | SWC-107 |

## Description
`withdraw()` envoie l'ETH via `call` **avant** de remettre le solde de l'appelant à zéro.
Un contrat destinataire peut, dans sa fonction `receive()`, rappeler `withdraw()` alors
que `balances[msg.sender]` n'a pas encore été modifié.

## Cause racine
Violation du pattern Checks-Effects-Interactions : l'état est mis à jour après l'appel externe.

## Impact
Vidage complet du coffre : avec 1 ETH déposé, l'attaquant récupère les 10 ETH des autres
utilisateurs (11 ETH au total, 10 réentrées). Perte de fonds pour tous les déposants.

## Preuve (PoC)
`forge test --match-test test_PoC_ReentrancyDrainsVault -vvv`
```
Reentrees      : 10
Vault restant  : 0
Gain attaquant : 11000000000000000000
```

## Correctif
1. Réordonnancement CEI : `balances[msg.sender] = 0` avant `call`.
2. Défense en profondeur : modificateur `nonReentrant` (OpenZeppelin `ReentrancyGuard`).
3. Erreurs custom (`TransferFailed`, …) pour des tests précis et moins de gas.

## Validation
| Test | Résultat |
|---|---|
| `test_Regression_ReentrancyBlocked` | ✅ l'attaque revert, 10 ETH intacts |
| `testFuzz_WithdrawExactDeposit` (1000 runs) | ✅ |
| `invariant_Solvency` (256 runs × 50 appels) | ✅ |
| `invariant_Accounting` | ✅ |
| Slither sur `SecureVault` | `reentrancy-eth` disparu |

## Analyse Slither — triage
| Finding | Contrat | Verdict |
|---|---|---|
| `reentrancy-eth` | VulnerableVault | **Vrai positif** — exploité par le PoC |
| `reentrancy-events` | VulnerableVault | Vrai positif (conséquence de la même cause) |
| `low-level-calls` | SecureVault | **Accepté / informatif** — `call` est la méthode recommandée pour envoyer de l'ETH (`transfer` limite à 2300 gas) ; le risque est neutralisé par CEI + `nonReentrant` |

## Limites résiduelles
- `ReentrancyGuard` ne protège pas la **réentrance cross-contract** ni read-only
  (un autre protocole lisant `balances` pendant l'appel).
- Un destinataire qui revert bloque son propre retrait (pas les autres) — voir ES-06 (DoS).
