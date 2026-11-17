# ES-03 — Authentification par `tx.origin` dans `VulnerableWallet`

| Champ | Valeur |
|---|---|
| Sévérité | **Élevée** (Impact critique × Probabilité moyenne : nécessite que la victime interagisse avec un contrat piège) |
| Statut | Corrigé dans `SecureWallet` |
| Fichier | `src/vulnerable/VulnerableWallet.sol` L21 |
| Détecteur Slither | `tx-origin` (Medium) |
| SWC | SWC-115 (Authorization through tx.origin) |

## Description
`transfer()` vérifie `tx.origin == owner`. `tx.origin` désigne le compte (EOA) qui a **signé**
la transaction initiale, et non l'appelant direct. Si le propriétaire appelle un contrat
malveillant, ce contrat peut appeler le wallet : `tx.origin` vaut toujours le propriétaire,
et le contrôle est validé.

## `msg.sender` vs `tx.origin`
```
Alice (EOA) ──signe──> PhishingContract ──appelle──> VulnerableWallet
                                                       tx.origin  = Alice           ✅ check passé
                                                       msg.sender = PhishingContract ❌ ce qu'il fallait vérifier
```

## Cause racine
Confusion entre l'identité de l'**initiateur** de la transaction et celle de l'**appelant direct**.
L'autorisation doit porter sur `msg.sender`.

## Impact
Vidage complet du wallet (10 ETH dans le PoC) dès que le propriétaire interagit avec un
contrat contrôlé par l'attaquant (faux airdrop, faux mint NFT, etc.) : **phishing on-chain**.

## Preuve (PoC)
`forge test --match-path test/exploits/TxOrigin.t.sol -vvv`
```
[PASS] test_DirectAttackFails()       -> eve en direct : revert "not owner"
[PASS] test_PoC_PhishingViaTxOrigin() -> via le piège : wallet 0, eve +10 ETH
```
Note : `vm.prank(alice, alice)` fixe à la fois `msg.sender` ET `tx.origin`, ce qui simule une
transaction signée par Alice.

## Correctif
1. Remplacement par `msg.sender` via `Ownable` d'OpenZeppelin (`onlyOwner`).
2. Vérification d'adresse zéro, erreurs custom, événement émis avant l'appel externe (CEI).

## Validation
| Test | Résultat |
|---|---|
| `test_Regression_PhishingBlocked` | ✅ revert `OwnableUnauthorizedAccount(phishing)`, 10 ETH intacts |
| `test_OwnerCanTransfer` | ✅ fonctionnement normal préservé |
| `testFuzz_OnlyDirectOwnerCall` (1000 couples `msg.sender`/`tx.origin` aléatoires) | ✅ |

## Analyse Slither — triage
| Finding | Contrat | Verdict |
|---|---|---|
| `tx-origin` | VulnerableWallet | **Vrai positif** — exploité par le PoC |
| *(aucun)* | SecureWallet | Finding disparu après correction |

Contraste avec ES-02 : ici la faille suit un **motif syntaxique** (`tx.origin` dans un `require`),
donc Slither la détecte. Les failles de **logique** (ES-02) lui échappent.

## Limites résiduelles
- `Ownable` = un seul propriétaire : si sa clé est volée, tout est perdu. Recommandation :
  multisig, ou `Ownable2Step` pour éviter un transfert de propriété vers une mauvaise adresse.
- `require(tx.origin == msg.sender)` pour « bloquer les contrats » est aussi déconseillé :
  depuis EIP-7702 (Pectra, 2025), un EOA peut exécuter du code, ce test n'est donc plus fiable.
