// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

interface ISwapRouter {
    function swap(
        bytes memory extCallData
    ) external payable returns (uint256 returnAmount, uint256 gasUsed);
}
