// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VulnerableAuction} from "../src/vulnerable/VulnerableAuction.sol";
import {SecureAuction} from "../src/fixed/SecureAuction.sol";

/// Usage (Anvil uniquement) :
///   forge script script/DeployDenialOfService.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
contract DeployDenialOfService is Script {
    function run() external {
        require(block.chainid == 31337, "LAB ONLY: Anvil chainId 31337");
        uint256 pk =
            vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        vm.startBroadcast(pk);
        VulnerableAuction vuln = new VulnerableAuction(1 days);
        SecureAuction secure = new SecureAuction(1 days);
        vm.stopBroadcast();
        console2.log("VulnerableAuction:", address(vuln));
        console2.log("SecureAuction    :", address(secure));
    }
}
