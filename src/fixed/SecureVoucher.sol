// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/// @title SecureVoucher — correctif de ES-04
/// @notice Signatures EIP-712 avec :
///  - nonce par bénéficiaire  -> une signature n'est valable qu'UNE fois
///  - deadline                -> une signature expire
///  - domaine EIP-712         -> liée à CE contrat et à CETTE chaîne (chainId)
///  - ECDSA d'OpenZeppelin    -> rejette les signatures malléables
contract SecureVoucher is EIP712, Nonces {
    bytes32 public constant VOUCHER_TYPEHASH =
        keccak256("Voucher(address to,uint256 amount,uint256 nonce,uint256 deadline)");

    address public immutable signer;

    event Claimed(address indexed to, uint256 amount, uint256 nonce);

    error Expired(uint256 deadline);
    error BadSignature(address recovered);
    error TransferFailed();

    constructor(address _signer) payable EIP712("EtherShieldVoucher", "1") {
        signer = _signer;
    }

    receive() external payable {}

    function claim(address payable to, uint256 amount, uint256 deadline, bytes calldata signature) external {
        // CHECKS
        if (block.timestamp > deadline) revert Expired(deadline);
        uint256 nonce = _useNonce(to); // EFFECT : nonce consommé avant tout transfert
        bytes32 structHash = keccak256(abi.encode(VOUCHER_TYPEHASH, to, amount, nonce, deadline));
        address recovered = ECDSA.recover(_hashTypedDataV4(structHash), signature);
        if (recovered != signer) revert BadSignature(recovered);

        // INTERACTIONS
        emit Claimed(to, amount, nonce);
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    /// Exposé pour les signataires hors-chaîne et les tests.
    function hashVoucher(address to, uint256 amount, uint256 nonce, uint256 deadline) external view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(VOUCHER_TYPEHASH, to, amount, nonce, deadline)));
    }
}
