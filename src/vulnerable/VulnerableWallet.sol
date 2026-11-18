// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title VulnerableWallet — LAB ONLY, intentionally vulnerable
/// @notice Portefeuille personnel d'un utilisateur.
/// FINDING ES-03 : authentification via tx.origin au lieu de msg.sender.
contract VulnerableWallet {
    address public owner;

    event Transfer(address indexed to, uint256 amount);

    constructor() payable {
        owner = msg.sender;
    }

    receive() external payable {}

    /// @dev tx.origin = le compte (EOA) qui a SIGNÉ la transaction d'origine,
    ///      même si l'appel passe par un contrat intermédiaire malveillant.
    function transfer(address payable to, uint256 amount) external {
        require(tx.origin == owner, "not owner");
        (bool ok,) = to.call{value: amount}("");
        require(ok, "transfer failed");
        emit Transfer(to, amount);
    }
}
