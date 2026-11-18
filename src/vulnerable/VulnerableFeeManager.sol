// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title VulnerableFeeManager — LAB ONLY, intentionally vulnerable
/// @notice Encaisse des frais sur des paiements et les reverse à une trésorerie.
/// FINDING ES-02a : setTreasury() / setFeeBps() sans contrôle d'accès.
/// FINDING ES-02b : initialize() peut être rappelée par n'importe qui (prise de contrôle).
contract VulnerableFeeManager {
    address public owner;
    address public treasury;
    uint256 public feeBps; // 100 bps = 1 %
    uint256 public collectedFees;
    bool public initialized;

    event Paid(address indexed payer, address indexed to, uint256 amount, uint256 fee);
    event TreasuryChanged(address treasury);
    event FeeChanged(uint256 feeBps);

    /// @dev ES-02b : le flag "initialized" n'est jamais vérifié.
    function initialize(address _owner, address _treasury, uint256 _feeBps) external {
        owner = _owner;
        treasury = _treasury;
        feeBps = _feeBps;
        initialized = true;
    }

    /// @dev ES-02a : fonction critique sans aucune vérification de msg.sender.
    function setTreasury(address _treasury) external {
        treasury = _treasury;
        emit TreasuryChanged(_treasury);
    }

    /// @dev ES-02a : aucune vérification + aucune borne (jusqu'à 100 %).
    function setFeeBps(uint256 _feeBps) external {
        feeBps = _feeBps;
        emit FeeChanged(_feeBps);
    }

    /// Paie `to` en prélevant des frais.
    function pay(address payable to) external payable {
        uint256 fee = (msg.value * feeBps) / 10_000;
        collectedFees += fee;
        (bool ok,) = to.call{value: msg.value - fee}("");
        require(ok, "pay failed");
        emit Paid(msg.sender, to, msg.value, fee);
    }

    /// Reverse les frais à la trésorerie (qui peut avoir été détournée).
    function withdrawFees() external {
        uint256 amount = collectedFees;
        collectedFees = 0;
        (bool ok,) = treasury.call{value: amount}("");
        require(ok, "withdraw failed");
    }
}
