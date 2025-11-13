// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

contract SwapAggregator {
    address public immutable i_swapRouter; // Address for now

    constructor(address swapRouter){
        i_swapRouter = swapRouter;
    }
}