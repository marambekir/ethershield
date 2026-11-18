// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SecureAuction — correctif de ES-06
/// @notice Pattern "pull over push" : les anciens leaders ne sont PAS remboursés pendant bid().
///         Leur montant est crédité dans pendingReturns et ils le RETIRENT eux-mêmes.
///         Un destinataire qui refuse l'ETH ne bloque donc que lui-même.
contract SecureAuction is ReentrancyGuard {
    address public highestBidder;
    uint256 public highestBid;
    uint256 public immutable endTime;
    address public immutable seller;
    bool public ended;
    mapping(address => uint256) public pendingReturns;

    event NewBid(address indexed bidder, uint256 amount);
    event Withdrawn(address indexed bidder, uint256 amount);
    event AuctionEnded(address winner, uint256 amount);

    error AuctionOver();
    error AuctionNotOver();
    error AlreadyEnded();
    error BidTooLow(uint256 bid, uint256 highestBid);
    error NothingToWithdraw();
    error TransferFailed();

    constructor(uint256 duration) {
        seller = msg.sender;
        endTime = block.timestamp + duration;
    }

    function bid() external payable {
        if (block.timestamp >= endTime) revert AuctionOver();
        if (msg.value <= highestBid) revert BidTooLow(msg.value, highestBid);

        // Aucun appel externe : on crédite simplement l'ancien leader.
        if (highestBidder != address(0)) {
            pendingReturns[highestBidder] += highestBid;
        }
        highestBidder = msg.sender;
        highestBid = msg.value;
        emit NewBid(msg.sender, msg.value);
    }

    /// Chaque enchérisseur dépassé récupère lui-même ses fonds.
    function withdraw() external nonReentrant {
        uint256 amount = pendingReturns[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        pendingReturns[msg.sender] = 0;
        emit Withdrawn(msg.sender, amount);
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    function endAuction() external nonReentrant {
        if (block.timestamp < endTime) revert AuctionNotOver();
        if (ended) revert AlreadyEnded();
        ended = true;
        emit AuctionEnded(highestBidder, highestBid);
        pendingReturns[seller] += highestBid; // le vendeur retire aussi (pull)
    }
}
