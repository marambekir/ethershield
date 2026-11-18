// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {SecureAMM} from "../../src/fixed/SecureAMM.sol";
import {MockToken} from "../mocks/MockToken.sol";

/// @notice Non-régression ES-05 : le sandwich ne doit plus voler la victime.
contract SecureAMMTest is Test {
    SecureAMM amm;
    MockToken tA;
    MockToken tB;
    address lp = makeAddr("lp");
    address alice = makeAddr("alice");
    address eve = makeAddr("eve");
    uint256 constant SLIPPAGE_BPS = 50; // tolérance 0,5 %

    function setUp() public {
        tA = new MockToken("Token A", "TKA");
        tB = new MockToken("Token B", "TKB");
        amm = new SecureAMM(tA, tB);
        tA.mint(lp, 100 ether);
        tB.mint(lp, 100 ether);
        vm.startPrank(lp);
        tA.approve(address(amm), type(uint256).max);
        tB.approve(address(amm), type(uint256).max);
        amm.addLiquidity(100 ether, 100 ether);
        vm.stopPrank();
        tA.mint(alice, 10 ether);
        vm.prank(alice);
        tA.approve(address(amm), type(uint256).max);
        tA.mint(eve, 30 ether);
        vm.startPrank(eve);
        tA.approve(address(amm), type(uint256).max);
        tB.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }

    function _minOut(uint256 q) internal pure returns (uint256) {
        return q * (10_000 - SLIPPAGE_BPS) / 10_000;
    }

    function test_NormalSwapWithinSlippage() public {
        uint256 q = amm.quote(address(tA), 10 ether);
        vm.prank(alice);
        uint256 out = amm.swap(address(tA), 10 ether, _minOut(q), block.timestamp + 60);
        assertEq(out, q);
    }

    function test_Regression_SandwichReverts() public {
        // alice signe sa transaction avec le devis du moment
        uint256 q = amm.quote(address(tA), 10 ether);
        uint256 minOut = _minOut(q);

        vm.prank(eve);
        uint256 eveB = amm.swap(address(tA), 30 ether, 0, block.timestamp + 60); // front-run

        uint256 degraded = amm.quote(address(tA), 10 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SecureAMM.SlippageExceeded.selector, degraded, minOut));
        amm.swap(address(tA), 10 ether, minOut, block.timestamp + 60);

        assertEq(tA.balanceOf(alice), 10 ether, "alice keeps her tokens");

        // back-run : sans victime au milieu, eve PERD de l'argent (frais 2 x 0,3 %)
        vm.prank(eve);
        uint256 eveA = amm.swap(address(tB), eveB, 0, block.timestamp + 60);
        assertLt(eveA, 30 ether, "attack is unprofitable");
    }

    function test_Regression_ExpiredTransaction() public {
        uint256 deadline = block.timestamp + 60;
        vm.warp(deadline + 1); // transaction gardée en attente trop longtemps
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SecureAMM.Expired.selector, deadline));
        amm.swap(address(tA), 10 ether, 0, deadline);
    }

    /// Fuzzing : quelle que soit la taille du front-run, alice reçoit >= minOut, ou revert.
    function testFuzz_VictimNeverBelowMinOut(uint256 frontrun) public {
        frontrun = bound(frontrun, 0.001 ether, 1_000 ether);
        tA.mint(eve, frontrun);

        uint256 minOut = _minOut(amm.quote(address(tA), 10 ether));
        vm.prank(eve);
        amm.swap(address(tA), frontrun, 0, block.timestamp + 60);

        vm.prank(alice);
        try amm.swap(address(tA), 10 ether, minOut, block.timestamp + 60) returns (uint256 out) {
            assertGe(out, minOut);
        } catch {
            assertEq(tA.balanceOf(alice), 10 ether);
        }
    }
}

contract AMMHandler is Test {
    SecureAMM public amm;
    MockToken public tA;
    MockToken public tB;

    constructor(SecureAMM _amm, MockToken _a, MockToken _b) {
        amm = _amm;
        tA = _a;
        tB = _b;
        tA.approve(address(amm), type(uint256).max);
        tB.approve(address(amm), type(uint256).max);
    }

    function swapAtoB(uint256 amount) external {
        amount = bound(amount, 1e6, 50 ether);
        tA.mint(address(this), amount);
        amm.swap(address(tA), amount, 0, block.timestamp);
    }

    function swapBtoA(uint256 amount) external {
        amount = bound(amount, 1e6, 50 ether);
        tB.mint(address(this), amount);
        amm.swap(address(tB), amount, 0, block.timestamp);
    }
}

contract SecureAMMInvariantTest is StdInvariant, Test {
    SecureAMM amm;
    MockToken tA;
    MockToken tB;
    AMMHandler handler;
    uint256 initialK;

    function setUp() public {
        tA = new MockToken("Token A", "TKA");
        tB = new MockToken("Token B", "TKB");
        amm = new SecureAMM(tA, tB);
        tA.mint(address(this), 100 ether);
        tB.mint(address(this), 100 ether);
        tA.approve(address(amm), type(uint256).max);
        tB.approve(address(amm), type(uint256).max);
        amm.addLiquidity(100 ether, 100 ether);
        initialK = amm.reserveA() * amm.reserveB();
        handler = new AMMHandler(amm, tA, tB);
        targetContract(address(handler));
    }

    /// x * y = k ne diminue jamais (les frais le font croître).
    function invariant_KNeverDecreases() public view {
        assertGe(amm.reserveA() * amm.reserveB(), initialK);
    }

    /// Les réserves comptables correspondent aux soldes réels.
    function invariant_ReservesMatchBalances() public view {
        assertEq(amm.reserveA(), tA.balanceOf(address(amm)));
        assertEq(amm.reserveB(), tB.balanceOf(address(amm)));
    }
}
