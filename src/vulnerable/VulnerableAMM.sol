// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title VulnerableAMM — LAB ONLY, intentionally vulnerable
/// @notice Pool d'échange à produit constant (x * y = k), frais 0,3 %, type Uniswap V2 simplifié.
/// FINDING ES-05 : swap() sans montant minimum garanti (slippage) ni date limite
///                 -> l'utilisateur accepte N'IMPORTE QUEL prix : attaque "sandwich".
contract VulnerableAMM {
    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;
    uint256 public reserveA;
    uint256 public reserveB;

    event Swap(address indexed user, address tokenIn, uint256 amountIn, uint256 amountOut);

    constructor(IERC20 _a, IERC20 _b) {
        tokenA = _a;
        tokenB = _b;
    }

    function addLiquidity(uint256 amountA, uint256 amountB) external {
        tokenA.transferFrom(msg.sender, address(this), amountA);
        tokenB.transferFrom(msg.sender, address(this), amountB);
        reserveA += amountA;
        reserveB += amountB;
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public pure returns (uint256)
    {
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    /// @dev Le résultat dépend de l'état des réserves AU MOMENT de l'exécution,
    ///      donc de l'ORDRE des transactions dans le bloc.
    function swap(address tokenIn, uint256 amountIn) external returns (uint256 amountOut) {
        bool aToB = tokenIn == address(tokenA);
        require(aToB || tokenIn == address(tokenB), "bad token");
        (IERC20 inTok, IERC20 outTok) = aToB ? (tokenA, tokenB) : (tokenB, tokenA);
        (uint256 rIn, uint256 rOut) = aToB ? (reserveA, reserveB) : (reserveB, reserveA);

        amountOut = getAmountOut(amountIn, rIn, rOut);

        inTok.transferFrom(msg.sender, address(this), amountIn);
        if (aToB) { reserveA += amountIn; reserveB -= amountOut; }
        else      { reserveB += amountIn; reserveA -= amountOut; }
        outTok.transfer(msg.sender, amountOut);
        emit Swap(msg.sender, tokenIn, amountIn, amountOut);
    }
}
