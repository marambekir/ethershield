# ES-06 — Déni de service par remboursement « push » dans `VulnerableAuction`

| Champ | Valeur |
|---|---|
| Sévérité | **Élevée** (Impact élevé : enchère gelée, vendeur lésé × Probabilité élevée : attaque triviale, coût = une offre) |
| Statut | Corrigé dans `SecureAuction` |
| Fichier | `src/vulnerable/VulnerableAuction.sol` L23-36 |
| Détecteur Slither | `reentrancy-eth` (détection **indirecte**, voir triage) |
| SWC | SWC-113 (DoS with Failed Call) |

## Description
`bid()` rembourse l'ancien meilleur enchérisseur **dans la même transaction** que la nouvelle
offre, et exige que ce remboursement réussisse (`require(ok)`). Un attaquant enchérit depuis
un contrat qui **refuse l'ETH** (pas de `receive()`). Toute offre supérieure tente de le
rembourser, échoue, et fait **revert l'offre entière**. L'attaquant reste leader à vie.

## Cause racine
Le succès d'une opération critique (enchérir) dépend du bon vouloir d'un **tiers externe**
(l'ancien leader). Couplage d'un appel externe non maîtrisé avec la logique principale.

## Impact
| | Valeur |
|---|---|
| Offre de l'attaquant | 1,5 ETH |
| Offres bloquées | alice 10 ETH, bob 50 ETH |
| Gagnant | contrat d'eve, au prix de 1,5 ETH |
| Perte pour le vendeur | **48,5 ETH** de valeur non réalisée |

## Preuve (PoC)
`forge test --match-path test/exploits/DenialOfService.t.sol -vv`
```
[PASS] test_NormalBidding()                      -> fonctionnement normal sans attaquant
[PASS] test_PoC_AuctionBlockedByRevertingBidder() -> offres de 10 et 50 ETH : revert "refund failed"
  Prix paye          : 1500000000000000000
  Offre bloquee (bob): 50000000000000000000
```

## Correctif : pattern « pull over push »
1. `bid()` ne fait **plus aucun appel externe** : l'ancien leader est crédité dans
   `pendingReturns[addr]`.
2. Chacun récupère ses fonds via `withdraw()` (CEI + `nonReentrant`).
3. Le vendeur est payé de la même façon à la fin de l'enchère.

Un destinataire qui refuse l'ETH ne bloque désormais **que son propre retrait**.

## Validation
| Test | Résultat |
|---|---|
| `test_Regression_RevertingBidderCannotBlock` | ✅ bob surenchérit à 50 ETH, les 1,5 ETH d'eve restent crédités |
| `test_FullAuctionFlowWithPull` | ✅ enchère complète, contrat vidé proprement |
| `test_CannotWithdrawTwice` / `test_CannotEndTwice` | ✅ |
| `testFuzz_HigherBidAlwaysAccepted` (1000 couples d'offres) | ✅ |
| `invariant_Solvency` (12 800 appels dont ~4300 offres hostiles) | ✅ solde = offre en tête + montants dus |

## Analyse Slither — triage
| Finding | Contrat | Verdict |
|---|---|---|
| `reentrancy-eth` sur `bid()` | Vulnerable | **Vrai positif, mauvaise catégorie** : Slither signale l'appel externe avant mise à jour de l'état (risque réel de réentrance), mais **ne nomme pas le DoS**. La même cause racine produit les deux failles. Le déni de service a été identifié par revue manuelle + PoC |
| `reentrancy-events` | Vulnerable | Informatif |
| `timestamp` sur `bid()` | Secure | **Accepté** : un validateur ne peut décaler `endTime` que de quelques secondes |
| *(aucun)* sur `withdraw()` | Secure | CEI + `nonReentrant` reconnus |

## Limites résiduelles
- Le pull pattern déplace la charge vers l'utilisateur, qui doit **penser à retirer** ses fonds
  (coût en gas, UX). Une interface doit afficher clairement les montants dus.
- Une autre forme de DoS n'est pas couverte par ce module : la **boucle non bornée**
  (ex. rembourser une liste d'enchérisseurs qui grandit sans limite jusqu'à dépasser la
  limite de gas du bloc). Règle : jamais de boucle sur un tableau contrôlable par les
  utilisateurs ; utiliser le pull pattern ou la pagination.
- Les fonds d'un enchérisseur qui refuse l'ETH restent **bloqués à vie** dans le contrat
  (seulement les siens). Option : `withdrawTo(address)` pour qu'il puisse choisir un autre destinataire.
