// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title SecureWallet — correctif de ES-03
/// @notice Authentification via msg.sender (appelant DIRECT) grâce à Ownable.
contract SecureWallet is Ownable {
    event Transfer(address indexed to, uint256 amount);

    error ZeroAddress();
    error TransferFailed();

    constructor() payable Ownable(msg.sender) {}

    receive() external payable {}

    function transfer(address payable to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        emit Transfer(to, amount);
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
