// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

struct LeverageParams {
    uint256 desiredLtv;
    address collateralToken;
    address loanToken;
    uint256 amountCollateral;
    // Swap Data
}

struct DeleverageParams {
    uint256 desiredLtv;
    address collateralToken;
    address loanToken;
    uint256 sharesToBurn;
    uint256 amountCollateralToWithdraw;
    // Swap Data
}