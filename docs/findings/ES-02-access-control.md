# ES-02 — Contrôle d'accès manquant dans `VulnerableFeeManager`

| Champ | Valeur |
|---|---|
| Sévérité | **Critique** (Impact élevé × Probabilité élevée : exploitable par n'importe qui, sans prérequis) |
| Statut | Corrigé dans `SecureFeeManager` |
| Fichier | `src/vulnerable/VulnerableFeeManager.sol` |
| Détecteur Slither | **Aucun** (faux négatif, voir triage) |
| SWC | SWC-105 (Unprotected Ether Withdrawal), SWC-118 (Incorrect Constructor / initializer) |

## Description
- **ES-02a** : `setTreasury()` et `setFeeBps()` ne vérifient pas `msg.sender`. N'importe quel
  compte peut rediriger la trésorerie ou fixer les frais à 100 %.
- **ES-02b** : `initialize()` positionne un flag `initialized` mais ne le vérifie jamais.
  Un attaquant peut la rappeler et devenir `owner`.

## Cause racine
Absence de modèle d'autorisation : les fonctions qui modifient des paramètres critiques
n'ont aucun modificateur (`onlyOwner`, `onlyRole`) et l'initialisation n'est pas protégée
contre le rejeu.

## Impact
| Scénario | Conséquence |
|---|---|
| Redirection de trésorerie | Vol de 100 % des frais collectés (1 ETH dans le PoC) |
| Frais à 100 % | Les marchands ne reçoivent plus rien : vol de chaque paiement |
| Réinitialisation | Prise de contrôle totale du protocole |

## Preuve (PoC)
`forge test --match-path test/exploits/AccessControl.t.sol -vvv`
```
[PASS] test_PoC_AnyoneCanRedirectTreasury()   -> eve reçoit 1 ETH, trésorerie 0
[PASS] test_PoC_AnyoneCanSetFeeTo100Percent() -> marchand reçoit 0
[PASS] test_PoC_ReinitializeTakeover()        -> owner == eve
```

## Correctif
1. `AccessControl` d'OpenZeppelin avec **rôles séparés** (moindre privilège) :
   `DEFAULT_ADMIN_ROLE` (gestion des rôles), `TREASURY_ROLE`, `FEE_MANAGER_ROLE`.
2. Initialisation dans le **constructeur** : impossible à rejouer.
   (Pour un contrat upgradeable : `Initializable` + modificateur `initializer`.)
3. **Borne codée en dur** `MAX_FEE_BPS = 500` (5 %) : limite l'impact même si un rôle est compromis.
4. Vérifications d'adresse zéro et événements avec ancienne/nouvelle valeur (traçabilité).

## Validation
| Test | Résultat |
|---|---|
| `test_Regression_CannotRedirectTreasury` | ✅ revert `AccessControlUnauthorizedAccount` |
| `test_Regression_CannotChangeFee` | ✅ |
| `test_Regression_FeeIsBoundedEvenForAdmin` | ✅ revert `FeeTooHigh` |
| `test_Regression_EveCannotGrantHerselfRoles` | ✅ |
| `test_LeastPrivilege` / `test_AdminCanRevoke` | ✅ |
| `testFuzz_NoRoleNoAccess` (1000 adresses aléatoires) | ✅ |
| `invariant_TreasuryUnchanged`, `invariant_FeeBounded`, `invariant_NoRoleEscalation` (12 800 appels hostiles) | ✅ |

## Analyse Slither — triage
| Finding | Contrat | Verdict |
|---|---|---|
| *(aucun détecteur)* sur `setTreasury` / `setFeeBps` / `initialize` | Vulnerable | **Faux négatif** : Slither n'a pas de détecteur générique « fonction d'administration non protégée ». Faille trouvée par revue manuelle + PoC |
| `missing-zero-check` sur `setTreasury`, `initialize` | Vulnerable | Vrai positif (mineur), corrigé |
| `missing-zero-check` sur `pay(to)` | Secure | **Accepté** : choix du payeur, sans impact sur le protocole |
| `low-level-calls` | Les deux | Informatif : `call` est la méthode recommandée pour envoyer de l'ETH |
| `naming-convention` | Les deux | Style uniquement |

**Leçon** : un outil d'analyse statique ne remplace pas la revue manuelle. Les failles
*logiques* (qui a le droit de faire quoi) sont rarement détectées automatiquement.

## Limites résiduelles
- Si la clé `DEFAULT_ADMIN_ROLE` est compromise, l'attaquant peut tout reconfigurer
  (dans la limite de 5 %). Recommandation : multisig + `AccessControlDefaultAdminRules`
  (transfert d'admin en deux étapes avec délai) + timelock sur les changements.
- `withdrawFees()` est volontairement publique : sans risque puisque la destination est protégée.

## Note de méthode — bug trouvé dans nos propres tests
Lors d'une exécution, `invariant_TreasuryUnchanged` a échoué : le fuzzer réutilise les
adresses présentes dans le storage et a tiré l'adresse de l'**admin**, qui a légitimement le
droit de changer la trésorerie. Ce n'était pas une faille du contrat mais un invariant mal
spécifié. Correction : le handler exclut l'admin (`modifier notAdmin`). Leçon : un invariant
doit décrire précisément **qui** est l'attaquant modélisé.
