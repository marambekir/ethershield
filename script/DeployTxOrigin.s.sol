// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VulnerableWallet} from "../src/vulnerable/VulnerableWallet.sol";
import {SecureWallet} from "../src/fixed/SecureWallet.sol";

/// Usage (Anvil uniquement) :
///   forge script script/DeployTxOrigin.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
contract DeployTxOrigin is Script {
    function run() external {
        require(block.chainid == 31337, "LAB ONLY: Anvil chainId 31337");
        uint256 pk =
            vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        vm.startBroadcast(pk);
        VulnerableWallet vuln = new VulnerableWallet{value: 10 ether}();
        SecureWallet secure = new SecureWallet{value: 10 ether}();
        vm.stopBroadcast();
        console2.log("VulnerableWallet:", address(vuln));
        console2.log("SecureWallet    :", address(secure));
    }
}
