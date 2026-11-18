// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title VulnerableVoucher — LAB ONLY, intentionally vulnerable
/// @notice Un signataire autorisé signe hors-chaîne des "bons" (destinataire, montant).
///         Le bénéficiaire les encaisse on-chain avec claim().
/// FINDING ES-04 : la signature ne contient ni nonce, ni expiration, ni domaine
///                 (chainId + adresse du contrat) -> elle peut être rejouée.
contract VulnerableVoucher {
    address public immutable signer;

    event Claimed(address indexed to, uint256 amount);

    constructor(address _signer) payable {
        signer = _signer;
    }

    receive() external payable {}

    /// @dev Message signé = keccak256(to, amount) : identique à chaque fois.
    function claim(address payable to, uint256 amount, uint8 v, bytes32 r, bytes32 s) external {
        bytes32 hash = keccak256(abi.encodePacked(to, amount));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        address recovered = ecrecover(ethHash, v, r, s); // brut : pas de contrôle de malléabilité
        require(recovered == signer, "bad signature");

        (bool ok,) = to.call{value: amount}("");
        require(ok, "transfer failed");
        emit Claimed(to, amount);
    }
}
