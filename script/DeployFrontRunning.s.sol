// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VulnerableAMM} from "../src/vulnerable/VulnerableAMM.sol";
import {MockToken} from "../test/mocks/MockToken.sol";

/// Prépare la démo ES-05 sur Anvil : pool 100/100, alice (compte n°1) et eve (compte n°2).
///   forge script script/DeployFrontRunning.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
contract DeployFrontRunning is Script {
    // Clés publiques des comptes de test Anvil n°0, n°1, n°2 (fonds fictifs)
    uint256 constant DEPLOYER = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant ALICE = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant EVE = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;

    function run() external {
        require(block.chainid == 31337, "LAB ONLY: Anvil chainId 31337");
        address alice = vm.addr(ALICE);
        address eve = vm.addr(EVE);

        vm.startBroadcast(DEPLOYER);
        MockToken tA = new MockToken("Token A", "TKA");
        MockToken tB = new MockToken("Token B", "TKB");
        VulnerableAMM amm = new VulnerableAMM(tA, tB);
        tA.mint(vm.addr(DEPLOYER), 100 ether);
        tB.mint(vm.addr(DEPLOYER), 100 ether);
        tA.approve(address(amm), type(uint256).max);
        tB.approve(address(amm), type(uint256).max);
        amm.addLiquidity(100 ether, 100 ether);
        tA.mint(alice, 10 ether);
        tA.mint(eve, 30 ether);
        vm.stopBroadcast();

        vm.startBroadcast(ALICE);
        tA.approve(address(amm), type(uint256).max);
        vm.stopBroadcast();

        vm.startBroadcast(EVE);
        tA.approve(address(amm), type(uint256).max);
        tB.approve(address(amm), type(uint256).max);
        vm.stopBroadcast();

        console2.log("TokenA :", address(tA));
        console2.log("TokenB :", address(tB));
        console2.log("AMM    :", address(amm));
    }
}
