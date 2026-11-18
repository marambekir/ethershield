// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title VulnerableAuction — LAB ONLY, intentionally vulnerable
/// @notice Enchère : chaque nouvelle offre plus haute rembourse automatiquement l'ancien leader.
/// FINDING ES-06 : remboursement "push" dans bid(). Si le leader refuse l'ETH (revert),
///                 plus PERSONNE ne peut enchérir : l'enchère est bloquée (Denial of Service).
contract VulnerableAuction {
    address public highestBidder;
    uint256 public highestBid;
    uint256 public immutable endTime;
    address public immutable seller;
    bool public ended;

    event NewBid(address indexed bidder, uint256 amount);
    event AuctionEnded(address winner, uint256 amount);

    constructor(uint256 duration) {
        seller = msg.sender;
        endTime = block.timestamp + duration;
    }

    function bid() external payable {
        require(block.timestamp < endTime, "auction over");
        require(msg.value > highestBid, "bid too low");

        // Remboursement immédiat de l'ancien leader : son échec fait échouer TOUTE l'offre.
        if (highestBidder != address(0)) {
            (bool ok,) = highestBidder.call{value: highestBid}("");
            require(ok, "refund failed");
        }

        highestBidder = msg.sender;
        highestBid = msg.value;
        emit NewBid(msg.sender, msg.value);
    }

    function endAuction() external {
        require(block.timestamp >= endTime, "not ended");
        require(!ended, "already ended");
        ended = true;
        emit AuctionEnded(highestBidder, highestBid);
        (bool ok,) = seller.call{value: highestBid}("");
        require(ok, "payout failed");
    }
}
