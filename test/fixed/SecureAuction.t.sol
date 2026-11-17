// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {SecureAuction} from "../../src/fixed/SecureAuction.sol";
import {DoSAttacker} from "../exploits/DoSAttacker.sol";

/// @notice Non-régression ES-06 : un enchérisseur hostile ne bloque plus personne.
contract SecureAuctionTest is Test {
    SecureAuction auction;
    DoSAttacker attacker;
    address seller = makeAddr("seller");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address eve = makeAddr("eve");

    function setUp() public {
        vm.prank(seller);
        auction = new SecureAuction(1 days);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(eve, 2 ether);
        vm.prank(eve);
        attacker = new DoSAttacker();
    }

    function test_Regression_RevertingBidderCannotBlock() public {
        vm.prank(alice); auction.bid{value: 1 ether}();
        vm.prank(eve);   attacker.attack{value: 1.5 ether}(address(auction));

        vm.prank(bob);
        auction.bid{value: 50 ether}(); // passe sans problème
        assertEq(auction.highestBidder(), bob);

        // les fonds d'eve restent crédités : elle ne bloque qu'elle-même
        assertEq(auction.pendingReturns(address(attacker)), 1.5 ether);
    }

    function test_FullAuctionFlowWithPull() public {
        vm.prank(alice); auction.bid{value: 1 ether}();
        vm.prank(bob);   auction.bid{value: 3 ether}();

        vm.prank(alice); auction.withdraw();
        assertEq(alice.balance, 100 ether);

        vm.warp(block.timestamp + 1 days);
        auction.endAuction();
        vm.prank(seller); auction.withdraw();
        assertEq(seller.balance, 3 ether);
        assertEq(address(auction).balance, 0);
    }

    function test_CannotWithdrawTwice() public {
        vm.prank(alice); auction.bid{value: 1 ether}();
        vm.prank(bob);   auction.bid{value: 2 ether}();
        vm.startPrank(alice);
        auction.withdraw();
        vm.expectRevert(SecureAuction.NothingToWithdraw.selector);
        auction.withdraw();
        vm.stopPrank();
    }

    function test_CannotEndTwice() public {
        vm.prank(alice); auction.bid{value: 1 ether}();
        vm.warp(block.timestamp + 1 days);
        auction.endAuction();
        vm.expectRevert(SecureAuction.AlreadyEnded.selector);
        auction.endAuction();
    }

    /// Fuzzing : quelle que soit l'offre de l'attaquant, une offre supérieure passe toujours.
    function testFuzz_HigherBidAlwaysAccepted(uint96 attackBid, uint96 extra) public {
        attackBid = uint96(bound(attackBid, 1, 1_000 ether));
        extra = uint96(bound(extra, 1, 1_000 ether));
        vm.deal(eve, attackBid);
        vm.prank(eve);
        attacker.attack{value: attackBid}(address(auction));

        uint256 bobBid = uint256(attackBid) + extra;
        vm.deal(bob, bobBid);
        vm.prank(bob);
        auction.bid{value: bobBid}();
        assertEq(auction.highestBidder(), bob);
    }
}

/// Handler : enchères, retraits et attaquants qui refusent l'ETH, au hasard.
contract AuctionHandler is Test {
    SecureAuction public auction;
    address[] public bidders;
    DoSAttacker public attacker;

    constructor(SecureAuction _auction) {
        auction = _auction;
        attacker = new DoSAttacker();
        for (uint256 i; i < 4; i++) bidders.push(makeAddr(string(abi.encode("bidder", i))));
    }

    function bid(uint256 seed, uint96 raise) external {
        raise = uint96(bound(raise, 1, 10 ether));
        uint256 amount = auction.highestBid() + raise;
        address b = bidders[seed % bidders.length];
        vm.deal(b, amount);
        vm.prank(b);
        try auction.bid{value: amount}() {} catch {}
    }

    function hostileBid(uint96 raise) external {
        raise = uint96(bound(raise, 1, 10 ether));
        uint256 amount = auction.highestBid() + raise;
        vm.deal(address(this), amount);
        try attacker.attack{value: amount}(address(auction)) {} catch {}
    }

    function withdraw(uint256 seed) external {
        vm.prank(bidders[seed % bidders.length]);
        try auction.withdraw() {} catch {}
    }

    function totalPending() external view returns (uint256 s) {
        for (uint256 i; i < bidders.length; i++) s += auction.pendingReturns(bidders[i]);
        s += auction.pendingReturns(address(attacker));
    }
}

contract SecureAuctionInvariantTest is StdInvariant, Test {
    SecureAuction auction;
    AuctionHandler handler;

    function setUp() public {
        auction = new SecureAuction(365 days);
        handler = new AuctionHandler(auction);
        targetContract(address(handler));
    }

    /// Solvabilité : le contrat détient exactement l'offre en tête + tout ce qui est dû.
    function invariant_Solvency() public view {
        assertEq(address(auction).balance, auction.highestBid() + handler.totalPending());
    }
}
