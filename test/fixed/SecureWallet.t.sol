// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SecureWallet} from "../../src/fixed/SecureWallet.sol";
import {PhishingContract} from "../exploits/PhishingContract.sol";

/// @notice Non-régression ES-03 : le même phishing doit ÉCHOUER.
contract SecureWalletTest is Test {
    SecureWallet wallet;
    PhishingContract phishing;
    address alice = makeAddr("alice");
    address eve = makeAddr("eve");
    address bob = makeAddr("bob");

    function setUp() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        wallet = new SecureWallet{value: 10 ether}();
        vm.prank(eve);
        phishing = new PhishingContract();
    }

    function test_Regression_PhishingBlocked() public {
        // msg.sender vu par le wallet = le contrat piège, PAS alice
        vm.prank(alice, alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(phishing)));
        phishing.claimAirdrop(address(wallet));

        assertEq(address(wallet).balance, 10 ether, "funds intact");
        assertEq(eve.balance, 0);
    }

    function test_OwnerCanTransfer() public {
        vm.prank(alice);
        wallet.transfer(payable(bob), 3 ether);
        assertEq(bob.balance, 3 ether);
        assertEq(address(wallet).balance, 7 ether);
    }

    /// Fuzzing : quel que soit le tx.origin, seul msg.sender == owner passe.
    function testFuzz_OnlyDirectOwnerCall(address caller, address origin) public {
        vm.assume(caller != alice);
        vm.prank(caller, origin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        wallet.transfer(payable(caller), 1 ether);
        assertEq(address(wallet).balance, 10 ether);
    }
}
