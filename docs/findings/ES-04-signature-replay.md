# ES-04 — Rejeu de signature dans `VulnerableVoucher`

| Champ | Valeur |
|---|---|
| Sévérité | **Critique** (Impact élevé × Probabilité élevée : tout bénéficiaire d'un bon peut le rejouer) |
| Statut | Corrigé dans `SecureVoucher` |
| Fichier | `src/vulnerable/VulnerableVoucher.sol` L21-30 |
| Détecteur Slither | **Aucun** (faux négatif) |
| SWC | SWC-121 (Missing Protection against Signature Replay), SWC-117 (Signature Malleability) |

## Description
Le contrat paie le destinataire d'un « bon » signé hors-chaîne par un signataire autorisé.
Le message signé est `keccak256(to, amount)` : il ne contient **rien d'unique**.
- **ES-04a — Rejeu simple** : la même signature peut être soumise indéfiniment.
- **ES-04b — Rejeu inter-contrats / inter-chaînes** : la signature ne mentionne ni l'adresse
  du contrat ni le `chainId`, elle est valable sur tout déploiement utilisant le même signataire.
- **ES-04c — Malléabilité** : `ecrecover` brut accepte aussi `(r, n − s, v')`, une seconde
  signature valide calculable sans la clé privée.

## Cause racine
Le message signé n'identifie pas **une autorisation unique** : pas de nonce (unicité),
pas d'expiration (durée), pas de domaine (contexte), et vérification cryptographique incomplète.

## Impact
| Scénario | Conséquence (PoC) |
|---|---|
| Rejeu simple | 1 bon de 1 ETH encaissé 10 fois : contrat vidé (10 ETH) |
| Rejeu inter-contrats | bon signé pour `voucher` encaissé aussi sur `voucher2` |
| Malléabilité | contournement de toute protection basée sur le hash de la signature |

## Preuve (PoC)
`forge test --match-path test/exploits/SignatureReplay.t.sol -vvv`
```
[PASS] test_PoC_ReplaySameSignature()   -> 1 signature, 10 encaissements, contrat à 0
[PASS] test_PoC_CrossContractReplay()   -> bob payé par 2 contrats
[PASS] test_PoC_SignatureMalleability() -> signature (r, n-s) acceptée
```

## Correctif
1. **EIP-712** (`EIP712` d'OpenZeppelin) : le digest inclut un *domain separator*
   (nom, version, `chainId`, adresse du contrat) + des données typées lisibles par les wallets.
2. **Nonce** par bénéficiaire (`Nonces`), consommé **avant** le transfert (CEI).
3. **Deadline** : la signature expire.
4. **`ECDSA.recover`** d'OpenZeppelin : rejette `s` dans la moitié haute (malléabilité) et
   les signatures invalides (pas de retour silencieux de `address(0)`).

## Validation
| Test | Résultat |
|---|---|
| `test_ValidClaim` | ✅ fonctionnement normal, nonce incrémenté |
| `test_Regression_ReplayBlocked` | ✅ |
| `test_Regression_CrossContractReplayBlocked` | ✅ |
| `test_Regression_CrossChainReplayBlocked` (`vm.chainId(1)`) | ✅ |
| `test_Regression_ExpiredSignature` (`vm.warp`) | ✅ revert `Expired` |
| `test_Regression_MalleableSignatureRejected` | ✅ revert `ECDSAInvalidSignatureS` |
| `test_Regression_AmountTamperingBlocked` | ✅ |
| `testFuzz_WrongSignerRejected` (1000 clés aléatoires) | ✅ |
| `testFuzz_SequentialNonces` (rejeu immédiat après chaque bon) | ✅ |

## Analyse Slither — triage
| Finding | Contrat | Verdict |
|---|---|---|
| *(aucun détecteur)* sur l'absence de nonce / domaine | Vulnerable | **Faux négatif** : faille de conception, trouvée par revue manuelle |
| `arbitrary-send-eth` sur `claim()` | Secure | **Faux positif** : le destinataire est authentifié par une signature EIP-712 du signataire autorisé |
| `timestamp` (`block.timestamp > deadline`) | Secure | **Accepté** : un validateur ne peut décaler le timestamp que de quelques secondes, négligeable pour une expiration en heures |
| `missing-zero-check` sur `_signer` | Les deux | **Vrai positif mineur** : avec `ecrecover` brut, `signer = 0` ferait accepter toute signature invalide. Neutralisé par `ECDSA.recover` dans la version corrigée |
| `reentrancy-events` | Vulnerable | Informatif |

## Limites résiduelles
- La sécurité repose entièrement sur la **clé du signataire** : si elle fuit, l'attaquant
  signe ce qu'il veut. Recommandation : rotation de clé + plafond par bon / par période.
- Les nonces sont **séquentiels** : un bon n°2 ne peut pas être encaissé avant le n°1.
  Si l'ordre ne doit pas compter, utiliser des nonces aléatoires stockés dans un `mapping`.
- Le signataire ne peut pas **annuler** un bon émis avant sa deadline (à ajouter si besoin).
