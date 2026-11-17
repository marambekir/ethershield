// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SecureAMM — correctif de ES-05
/// @notice L'utilisateur fixe :
///  - minAmountOut : prix plancher -> le sandwich fait revert la transaction au lieu de voler
///  - deadline     : la transaction ne peut pas être gardée en attente puis exécutée plus tard
contract SecureAMM {
    using SafeERC20 for IERC20;

    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;
    uint256 public reserveA;
    uint256 public reserveB;

    event Swap(address indexed user, address tokenIn, uint256 amountIn, uint256 amountOut);

    error BadToken();
    error Expired(uint256 deadline);
    error SlippageExceeded(uint256 amountOut, uint256 minAmountOut);

    constructor(IERC20 _a, IERC20 _b) {
        tokenA = _a;
        tokenB = _b;
    }

    function addLiquidity(uint256 amountA, uint256 amountB) external {
        tokenA.safeTransferFrom(msg.sender, address(this), amountA);
        tokenB.safeTransferFrom(msg.sender, address(this), amountB);
        reserveA += amountA;
        reserveB += amountB;
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public pure returns (uint256)
    {
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    /// Devis hors-chaîne : l'interface calcule minAmountOut = quote * (1 - tolérance).
    function quote(address tokenIn, uint256 amountIn) external view returns (uint256) {
        return tokenIn == address(tokenA)
            ? getAmountOut(amountIn, reserveA, reserveB)
            : getAmountOut(amountIn, reserveB, reserveA);
    }

    function swap(address tokenIn, uint256 amountIn, uint256 minAmountOut, uint256 deadline)
        external returns (uint256 amountOut)
    {
        if (block.timestamp > deadline) revert Expired(deadline);
        bool aToB = tokenIn == address(tokenA);
        if (!aToB && tokenIn != address(tokenB)) revert BadToken();
        (IERC20 inTok, IERC20 outTok) = aToB ? (tokenA, tokenB) : (tokenB, tokenA);
        (uint256 rIn, uint256 rOut) = aToB ? (reserveA, reserveB) : (reserveB, reserveA);

        amountOut = getAmountOut(amountIn, rIn, rOut);
        if (amountOut < minAmountOut) revert SlippageExceeded(amountOut, minAmountOut);

        if (aToB) { reserveA += amountIn; reserveB -= amountOut; }
        else      { reserveB += amountIn; reserveA -= amountOut; }
        inTok.safeTransferFrom(msg.sender, address(this), amountIn);
        outTok.safeTransfer(msg.sender, amountOut);
        emit Swap(msg.sender, tokenIn, amountIn, amountOut);
    }
}
