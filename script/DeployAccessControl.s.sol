// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VulnerableFeeManager} from "../src/vulnerable/VulnerableFeeManager.sol";
import {SecureFeeManager} from "../src/fixed/SecureFeeManager.sol";

/// Usage (Anvil uniquement) :
///   forge script script/DeployAccessControl.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
contract DeployAccessControl is Script {
    function run() external {
        require(block.chainid == 31337, "LAB ONLY: Anvil chainId 31337");
        // Compte n°0 d'Anvil = admin ; compte n°1 = trésorerie (fonds fictifs)
        uint256 pk = vm.envOr("PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address admin = vm.addr(pk);
        address treasury = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

        vm.startBroadcast(pk);
        VulnerableFeeManager vuln = new VulnerableFeeManager();
        vuln.initialize(admin, treasury, 100);
        SecureFeeManager secure = new SecureFeeManager(admin, treasury, 100);
        vm.stopBroadcast();

        console2.log("VulnerableFeeManager:", address(vuln));
        console2.log("SecureFeeManager    :", address(secure));
        console2.log("Admin               :", admin);
        console2.log("Treasury            :", treasury);
    }
}
