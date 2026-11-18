// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VulnerableVault} from "../src/vulnerable/VulnerableVault.sol";
import {SecureVault} from "../src/fixed/SecureVault.sol";

/// Usage (Anvil uniquement) :
///   anvil
///   forge script script/DeployReentrancy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
contract DeployReentrancy is Script {
    function run() external {
        require(block.chainid == 31337, "LAB ONLY: Anvil chainId 31337");
        // Clé privée publique n°0 d'Anvil (fonds fictifs)
        uint256 pk =
            vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        vm.startBroadcast(pk);
        VulnerableVault vuln = new VulnerableVault();
        SecureVault secure = new SecureVault();
        vuln.deposit{value: 10 ether}();
        secure.deposit{value: 10 ether}();
        vm.stopBroadcast();
        console2.log("VulnerableVault:", address(vuln));
        console2.log("SecureVault    :", address(secure));
    }
}
