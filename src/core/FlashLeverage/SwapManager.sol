// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @title SwapAggregator
 * @notice SwapAggregator is the contract that facilatates the token swaps via aggregator(s)
 * @dev Currently only using kyberswap
 */

import {ISwapRouter} from "../../interfaces/ISwapRouter.sol";

contract SwapManager {
    ISwapRouter public immutable i_swapRouter; // Only kyberswap

    constructor(address swapRouter) {
        i_swapRouter = ISwapRouter(swapRouter);
    }

    function _swap(bytes memory swapData) internal {
        i_swapRouter.swap(swapData);
    }
}
