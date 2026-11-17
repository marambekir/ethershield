// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {SecureVault} from "../../src/fixed/SecureVault.sol";
import {ReentrancyAttacker} from "../exploits/ReentrancyAttacker.sol";

/// @notice Non-régression ES-01 : la même attaque doit ÉCHOUER.
contract SecureVaultTest is Test {
    SecureVault vault;
    ReentrancyAttacker attacker;
    address alice = makeAddr("alice");
    address eve = makeAddr("eve");

    function setUp() public {
        vault = new SecureVault();
        vm.deal(alice, 10 ether);
        vm.deal(eve, 1 ether);
        vm.prank(alice); vault.deposit{value: 10 ether}();
        vm.prank(eve);
        attacker = new ReentrancyAttacker(address(vault));
    }

    function test_Regression_ReentrancyBlocked() public {
        vm.prank(eve);
        vm.expectRevert(SecureVault.TransferFailed.selector);
        attacker.attack{value: 1 ether}();
        assertEq(vault.totalAssets(), 10 ether, "funds must stay intact");
    }

    function test_NormalWithdraw() public {
        vm.prank(alice); vault.withdraw();
        assertEq(alice.balance, 10 ether);
        assertEq(vault.balances(alice), 0);
    }

    /// Fuzzing : quel que soit le montant, on ne retire jamais plus que son dépôt.
    function testFuzz_WithdrawExactDeposit(uint96 amount) public {
        vm.assume(amount > 0);
        address user = makeAddr("fuzzUser");
        vm.deal(user, amount);
        vm.startPrank(user);
        vault.deposit{value: amount}();
        vault.withdraw();
        vm.stopPrank();
        assertEq(user.balance, amount);
        assertEq(vault.totalAssets(), 10 ether);
    }
}

/// Handler pour les tests d'invariants : séquences aléatoires deposit/withdraw.
contract VaultHandler is Test {
    SecureVault public vault;
    address[] public actors;
    uint256 public ghostDeposited;
    uint256 public ghostWithdrawn;

    constructor(SecureVault _vault) {
        vault = _vault;
        for (uint256 i; i < 3; i++) actors.push(makeAddr(string(abi.encode(i))));
    }

    function deposit(uint256 seed, uint96 amount) external {
        amount = uint96(bound(amount, 1, 100 ether));
        address a = actors[seed % actors.length];
        vm.deal(a, amount);
        vm.prank(a); vault.deposit{value: amount}();
        ghostDeposited += amount;
    }

    function withdraw(uint256 seed) external {
        address a = actors[seed % actors.length];
        uint256 bal = vault.balances(a);
        if (bal == 0) return;
        vm.prank(a); vault.withdraw();
        ghostWithdrawn += bal;
    }

    function sumBalances() external view returns (uint256 s) {
        for (uint256 i; i < actors.length; i++) s += vault.balances(actors[i]);
    }
}

contract SecureVaultInvariantTest is StdInvariant, Test {
    SecureVault vault;
    VaultHandler handler;

    function setUp() public {
        vault = new SecureVault();
        handler = new VaultHandler(vault);
        targetContract(address(handler));
    }

    /// Solvabilité : le solde ETH couvre toujours la somme des dettes envers les utilisateurs.
    function invariant_Solvency() public view {
        assertEq(vault.totalAssets(), handler.sumBalances());
    }

    function invariant_Accounting() public view {
        assertEq(vault.totalAssets(), handler.ghostDeposited() - handler.ghostWithdrawn());
    }
}
