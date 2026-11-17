// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VulnerableVoucher} from "../src/vulnerable/VulnerableVoucher.sol";
import {SecureVoucher} from "../src/fixed/SecureVoucher.sol";

/// Usage (Anvil uniquement) :
///   forge script script/DeploySignatureReplay.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
contract DeploySignatureReplay is Script {
    function run() external {
        require(block.chainid == 31337, "LAB ONLY: Anvil chainId 31337");
        uint256 pk = vm.envOr("PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address signer = vm.addr(pk);
        vm.startBroadcast(pk);
        VulnerableVoucher vuln = new VulnerableVoucher{value: 10 ether}(signer);
        SecureVoucher secure = new SecureVoucher{value: 10 ether}(signer);
        vm.stopBroadcast();
        console2.log("VulnerableVoucher:", address(vuln));
        console2.log("SecureVoucher    :", address(secure));
        console2.log("Signer           :", signer);
    }
}
