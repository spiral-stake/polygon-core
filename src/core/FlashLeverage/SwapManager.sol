// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @title SwapAggregator
 * @notice SwapAggregator is the contract that facilatates the token swaps via aggregator(s)
 * @dev Currently only using kyberswap
 */

import {ISwapRouter} from "../../interfaces/ISwapRouter.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";

contract SwapManager is TokenHelper {
    ISwapRouter public immutable i_swapRouter; // Only kyberswap

    constructor(address swapRouter) {
        i_swapRouter = ISwapRouter(swapRouter);
    }

    function _swap(
        address tokenIn,
        uint256 amountIn,
        bytes memory swapData
    ) internal returns (uint256 returnAmount) {
        _forceApprove(tokenIn, address(i_swapRouter), amountIn);
        (returnAmount, ) = i_swapRouter.swap(swapData);
    }
}
