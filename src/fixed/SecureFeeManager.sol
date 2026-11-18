// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title SecureFeeManager — correctif de ES-02
/// @notice Rôles séparés (moindre privilège) :
///  - DEFAULT_ADMIN_ROLE : gère les rôles (idéalement un multisig)
///  - TREASURY_ROLE      : peut changer la trésorerie
///  - FEE_MANAGER_ROLE   : peut changer les frais, dans une borne fixe
contract SecureFeeManager is AccessControl {
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    uint256 public constant MAX_FEE_BPS = 500; // 5 % maximum, codé en dur

    address public treasury;
    uint256 public feeBps;
    uint256 public collectedFees;

    event Paid(address indexed payer, address indexed to, uint256 amount, uint256 fee);
    event TreasuryChanged(address indexed oldTreasury, address indexed newTreasury);
    event FeeChanged(uint256 oldFee, uint256 newFee);

    error ZeroAddress();
    error FeeTooHigh(uint256 feeBps);
    error TransferFailed();

    /// @dev Initialisation dans le constructeur : impossible à rejouer.
    constructor(address admin, address _treasury, uint256 _feeBps) {
        if (admin == address(0) || _treasury == address(0)) revert ZeroAddress();
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh(_feeBps);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(TREASURY_ROLE, admin);
        _grantRole(FEE_MANAGER_ROLE, admin);
        treasury = _treasury;
        feeBps = _feeBps;
    }

    function setTreasury(address _treasury) external onlyRole(TREASURY_ROLE) {
        if (_treasury == address(0)) revert ZeroAddress();
        emit TreasuryChanged(treasury, _treasury);
        treasury = _treasury;
    }

    function setFeeBps(uint256 _feeBps) external onlyRole(FEE_MANAGER_ROLE) {
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh(_feeBps);
        emit FeeChanged(feeBps, _feeBps);
        feeBps = _feeBps;
    }

    function pay(address payable to) external payable {
        uint256 fee = (msg.value * feeBps) / 10_000;
        collectedFees += fee;
        emit Paid(msg.sender, to, msg.value, fee);
        (bool ok,) = to.call{value: msg.value - fee}("");
        if (!ok) revert TransferFailed();
    }

    function withdrawFees() external {
        uint256 amount = collectedFees;
        collectedFees = 0;
        (bool ok,) = treasury.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
