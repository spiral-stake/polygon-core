// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

struct LeveragePosition {
    bool open;
    uint256 desiredLtv;
    address collateralToken;
    address loanToken;
    uint256 amountCollateral;
    address proxyContract; // Each Position is a separate proxy contract
    uint256 amountLeveragedCollateral; // Required when closing the position
    uint256 sharesBorrowed; // Required when closing the position
    uint256 amountCollateralInLoanToken; // Required for yield tracking and fees
}
