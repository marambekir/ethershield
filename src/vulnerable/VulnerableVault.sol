// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title VulnerableVault — LAB ONLY, intentionally vulnerable
/// @notice Coffre ETH simple. FINDING ES-01 : réentrance dans withdraw().
/// @dev NE JAMAIS DÉPLOYER hors d'un réseau local (Anvil).
contract VulnerableVault {
    mapping(address => uint256) public balances;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    function deposit() external payable {
        require(msg.value > 0, "zero deposit");
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    /// @dev Cause racine : l'interaction externe (call) a lieu AVANT la mise à jour de l'état.
    function withdraw() external {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "nothing to withdraw");

        // INTERACTION avant EFFECT -> le destinataire peut rappeler withdraw()
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");

        // unchecked : simule le comportement pré-0.8 (sinon l'underflow annulerait tout)
        unchecked {
            balances[msg.sender] -= amount;
        }
        emit Withdraw(msg.sender, amount);
    }

    function totalAssets() external view returns (uint256) {
        return address(this).balance;
    }
}
