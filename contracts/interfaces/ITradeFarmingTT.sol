//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

interface ITradeFarmingTT {
    /////////// Swap Functions ///////////
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /////////// Reward Functions ///////////

    function claimAllRewards() external;
}
