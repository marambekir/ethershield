// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {SecureFeeManager} from "../../src/fixed/SecureFeeManager.sol";

/// @notice Non-régression ES-02 : les mêmes attaques doivent ÉCHOUER.
contract SecureFeeManagerTest is Test {
    SecureFeeManager fm;
    address admin = makeAddr("admin");
    address treasury = makeAddr("treasury");
    address alice = makeAddr("alice");
    address shop = makeAddr("shop");
    address eve = makeAddr("eve");
    address feeOps = makeAddr("feeOps");

    function setUp() public {
        fm = new SecureFeeManager(admin, treasury, 100);
        vm.deal(alice, 100 ether);
        vm.prank(alice);
        fm.pay{value: 100 ether}(payable(shop));
    }

    function test_Regression_CannotRedirectTreasury() public {
        bytes32 role = fm.TREASURY_ROLE(); // lu AVANT vm.prank (sinon le prank est consommé)
        vm.prank(eve);
        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector, eve, role));
        fm.setTreasury(eve);

        fm.withdrawFees(); // n'importe qui peut déclencher, mais l'argent va au bon endroit
        assertEq(treasury.balance, 1 ether);
        assertEq(eve.balance, 0);
    }

    function test_Regression_CannotChangeFee() public {
        bytes32 role = fm.FEE_MANAGER_ROLE();
        vm.prank(eve);
        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector, eve, role));
        fm.setFeeBps(10_000);
    }

    function test_Regression_FeeIsBoundedEvenForAdmin() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SecureFeeManager.FeeTooHigh.selector, 10_000));
        fm.setFeeBps(10_000);
    }

    function test_Regression_EveCannotGrantHerselfRoles() public {
        bytes32 role = fm.FEE_MANAGER_ROLE();
        bytes32 adminRole = fm.DEFAULT_ADMIN_ROLE();
        vm.prank(eve);
        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector, eve, adminRole));
        fm.grantRole(role, eve);
    }

    /// Moindre privilège : feeOps peut changer les frais mais PAS la trésorerie.
    function test_LeastPrivilege() public {
        bytes32 feeRole = fm.FEE_MANAGER_ROLE();
        vm.prank(admin);
        fm.grantRole(feeRole, feeOps);

        vm.startPrank(feeOps);
        fm.setFeeBps(200);
        assertEq(fm.feeBps(), 200);
        vm.expectRevert();
        fm.setTreasury(feeOps);
        vm.stopPrank();
    }

    function test_AdminCanRevoke() public {
        bytes32 feeRole = fm.FEE_MANAGER_ROLE();
        vm.startPrank(admin);
        fm.grantRole(feeRole, feeOps);
        fm.revokeRole(feeRole, feeOps);
        vm.stopPrank();
        vm.prank(feeOps);
        vm.expectRevert();
        fm.setFeeBps(200);
    }

    /// Fuzzing : AUCUNE adresse sans rôle ne peut modifier la configuration.
    function testFuzz_NoRoleNoAccess(address caller, address newTreasury, uint256 newFee) public {
        vm.assume(caller != admin);
        vm.startPrank(caller);
        vm.expectRevert();
        fm.setTreasury(newTreasury);
        vm.expectRevert();
        fm.setFeeBps(newFee);
        vm.stopPrank();
        assertEq(fm.treasury(), treasury);
        assertEq(fm.feeBps(), 100);
    }

    /// Fuzzing : les frais restent bornés quoi que tente l'admin.
    function testFuzz_FeeAlwaysBounded(uint256 newFee) public {
        uint256 maxFee = fm.MAX_FEE_BPS();
        vm.prank(admin);
        if (newFee > maxFee) {
            vm.expectRevert();
            fm.setFeeBps(newFee);
        } else {
            fm.setFeeBps(newFee);
        }
        assertLe(fm.feeBps(), fm.MAX_FEE_BPS());
    }
}

/// Handler : des inconnus appellent au hasard toutes les fonctions sensibles.
contract AttackerHandler is Test {
    SecureFeeManager public fm;

    constructor(SecureFeeManager _fm) { fm = _fm; }

    function trySetTreasury(address caller, address t) external {
        vm.prank(caller);
        try fm.setTreasury(t) {} catch {}
    }

    function trySetFee(address caller, uint256 f) external {
        vm.prank(caller);
        try fm.setFeeBps(f) {} catch {}
    }

    function tryGrant(address caller, address who) external {
        bytes32 r = fm.TREASURY_ROLE();
        vm.prank(caller);
        try fm.grantRole(r, who) {} catch {}
    }

    function pay(uint96 amount) external {
        vm.deal(address(this), amount);
        try fm.pay{value: amount}(payable(address(0xBEEF))) {} catch {}
    }

    function withdraw() external { try fm.withdrawFees() {} catch {} }
}

contract SecureFeeManagerInvariantTest is StdInvariant, Test {
    SecureFeeManager fm;
    AttackerHandler handler;
    address admin = makeAddr("admin");
    address treasury = makeAddr("treasury");

    function setUp() public {
        fm = new SecureFeeManager(admin, treasury, 100);
        handler = new AttackerHandler(fm);
        targetContract(address(handler));
    }

    /// La trésorerie ne change jamais si l'admin n'agit pas.
    function invariant_TreasuryUnchanged() public view {
        assertEq(fm.treasury(), treasury);
    }

    /// Les frais ne dépassent jamais la borne.
    function invariant_FeeBounded() public view {
        assertLe(fm.feeBps(), fm.MAX_FEE_BPS());
    }

    /// Seul l'admin détient le rôle trésorerie.
    function invariant_NoRoleEscalation() public view {
        assertFalse(fm.hasRole(fm.TREASURY_ROLE(), address(handler)));
    }
}
