// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SecureVault — correctif de ES-01
/// @notice Défense en profondeur : Checks-Effects-Interactions + ReentrancyGuard.
contract SecureVault is ReentrancyGuard {
    mapping(address => uint256) public balances;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    error ZeroAmount();
    error NothingToWithdraw();
    error TransferFailed();

    function deposit() external payable {
        if (msg.value == 0) revert ZeroAmount();
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw() external nonReentrant {
        // CHECKS
        uint256 amount = balances[msg.sender];
        if (amount == 0) revert NothingToWithdraw();

        // EFFECTS
        balances[msg.sender] = 0;
        emit Withdraw(msg.sender, amount);

        // INTERACTIONS
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    function totalAssets() external view returns (uint256) {
        return address(this).balance;
    }
}
