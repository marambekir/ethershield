# EtherShield — Ethereum Smart Contract Security Lab

> ⚠️ **LAB ONLY.** Contrats volontairement vulnérables. Exécution exclusivement sur Anvil
> (chainId 31337), comptes et fonds fictifs. Interdiction de tester des contrats tiers
> ou des réseaux publics.

## Prérequis
```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup   # forge, anvil, cast
pip install slither-analyzer                               # analyse statique
git init && forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts@v5.1.0
```

## Structure
```
src/vulnerable/     contrats vulnérables (1 fichier = 1 classe de faille)
src/fixed/          versions corrigées
test/exploits/      PoC : prouvent que la faille EXISTE (doivent PASSER)
test/fixed/         non-régression, fuzzing, invariants (doivent PASSER)
script/             déploiement Anvil
docs/findings/      une fiche par finding (ES-XX)
```

## Commandes
| Commande | Rôle |
|---|---|
| `make test` | tous les tests |
| `make exploit` | PoC sur versions vulnérables |
| `make fixed` | non-régression + fuzz + invariants |
| `make anvil` puis `make deploy` | déploiement local |
| `make slither` | rapport Slither → `docs/slither-report.md` |

## Avancement
| ID | Vulnérabilité | Vulnérable | Corrigé | PoC | Fuzz/Invariant | Fiche |
|---|---|---|---|---|---|---|
| ES-01 | Reentrancy | ✅ | ✅ | ✅ | ✅ | ✅ |
| ES-02 | Access Control | ✅ | ✅ | ✅ | ✅ | ✅ |
| ES-03 | tx.origin | ✅ | ✅ | ✅ | ✅ | ✅ |
| ES-04 | Signature Replay | ✅ | ✅ | ✅ | ✅ | ✅ |
| ES-05 | Front-running / MEV | ✅ | ✅ | ✅ | ✅ | ✅ |
| ES-06 | Denial of Service | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |
