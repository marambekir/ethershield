// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SecureVoucher} from "../../src/fixed/SecureVoucher.sol";

/// @notice Non-régression ES-04 : les rejeux doivent ÉCHOUER.
contract SecureVoucherTest is Test {
    SecureVoucher voucher;
    SecureVoucher voucher2;
    uint256 signerPk = 0xA11CE;
    address signer;
    address bob = makeAddr("bob");

    function setUp() public {
        signer = vm.addr(signerPk);
        vm.deal(address(this), 20 ether);
        voucher = new SecureVoucher{value: 10 ether}(signer);
        voucher2 = new SecureVoucher{value: 10 ether}(signer);
    }

    function _sign(SecureVoucher v_, uint256 pk, address to, uint256 amount, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = v_.hashVoucher(to, amount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_ValidClaim() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(voucher, signerPk, bob, 1 ether, 0, deadline);
        voucher.claim(payable(bob), 1 ether, deadline, sig);
        assertEq(bob.balance, 1 ether);
        assertEq(voucher.nonces(bob), 1);
    }

    function test_Regression_ReplayBlocked() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(voucher, signerPk, bob, 1 ether, 0, deadline);
        voucher.claim(payable(bob), 1 ether, deadline, sig);

        // 2e tentative : le nonce attendu est 1, la signature portait 0 -> mauvais signataire récupéré
        vm.expectRevert();
        voucher.claim(payable(bob), 1 ether, deadline, sig);
        assertEq(bob.balance, 1 ether);
    }

    function test_Regression_CrossContractReplayBlocked() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(voucher, signerPk, bob, 1 ether, 0, deadline);
        vm.expectRevert(); // domaine différent (adresse du contrat) -> digest différent
        voucher2.claim(payable(bob), 1 ether, deadline, sig);
    }

    function test_Regression_CrossChainReplayBlocked() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(voucher, signerPk, bob, 1 ether, 0, deadline);
        vm.chainId(1); // même contrat, autre chaîne
        vm.expectRevert();
        voucher.claim(payable(bob), 1 ether, deadline, sig);
    }

    function test_Regression_ExpiredSignature() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(voucher, signerPk, bob, 1 ether, 0, deadline);
        vm.warp(deadline + 1);
        vm.expectRevert(abi.encodeWithSelector(SecureVoucher.Expired.selector, deadline));
        voucher.claim(payable(bob), 1 ether, deadline, sig);
    }

    function test_Regression_MalleableSignatureRejected() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = voucher.hashVoucher(bob, 1 ether, 0, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        uint256 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        bytes memory sig2 = abi.encodePacked(r, bytes32(n - uint256(s)), v == 27 ? uint8(28) : uint8(27));
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureS.selector, bytes32(n - uint256(s))));
        voucher.claim(payable(bob), 1 ether, deadline, sig2);
    }

    function test_Regression_AmountTamperingBlocked() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(voucher, signerPk, bob, 1 ether, 0, deadline);
        vm.expectRevert(); // bob tente de réclamer 5 ETH avec un bon de 1 ETH
        voucher.claim(payable(bob), 5 ether, deadline, sig);
    }

    /// Fuzzing : une signature d'un autre que le signataire autorisé est toujours rejetée.
    function testFuzz_WrongSignerRejected(uint256 pk) public {
        pk = bound(pk, 1, 115792089237316195423570985008687907852837564279074904382605163141518161494336);
        vm.assume(pk != signerPk);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(voucher, pk, bob, 1 ether, 0, deadline);
        vm.expectRevert();
        voucher.claim(payable(bob), 1 ether, deadline, sig);
    }

    /// Fuzzing : N bons signés avec des nonces successifs -> exactement N encaissements.
    function testFuzz_SequentialNonces(uint8 count) public {
        count = uint8(bound(count, 1, 10));
        uint256 deadline = block.timestamp + 1 hours;
        for (uint256 i; i < count; i++) {
            bytes memory sig = _sign(voucher, signerPk, bob, 1 ether, i, deadline);
            voucher.claim(payable(bob), 1 ether, deadline, sig);
            vm.expectRevert();
            voucher.claim(payable(bob), 1 ether, deadline, sig); // rejeu immédiat refusé
        }
        assertEq(bob.balance, uint256(count) * 1 ether);
        assertEq(voucher.nonces(bob), count);
    }
}
