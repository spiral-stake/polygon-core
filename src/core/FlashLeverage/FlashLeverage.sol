// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/// @notice FlashLeverage
/// @notice Provide flash loan based leveraged yields on yield bearing tokens using morpho markets
/// @dev Integrates with custom SwapAggregator and MarketPositionManager modules.
/// @dev Creates individual position proxy contracts for each user to isolate their positions.

import {MarketPositionManager, MarketParams, Id, UserProxy, IERC20Metadata, FLError, Math} from "./MarketPositionManager.sol";
import {SwapManager} from "./SwapManager.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {LeverageParams, DeleverageParams} from "../structs/LeverageParams.sol";
import {LeveragePosition} from "../structs/LeveragePosition.sol";
import {CollateralTokenConfig} from "../structs/CollateralTokenConfig.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IOracle} from "@morpho/interfaces/IOracle.sol";

contract FlashLeverage is
    MarketPositionManager,
    SwapManager,
    ReentrancyGuard,
    Ownable2Step
{
    using Math for uint256;

    /////////////////////////
    // Constants and Immutables

    /// @notice Buffer subtracted from liquidation LTV to determine the max LTV (18 decimals)
    uint256 public constant LIQUIDATION_BUFFER = 25e15; // 2.5%

    /// @notice Maximum allowed change in effective LTV after slippage from the swap (18 decimals)
    uint256 public constant SLIPPAGE_BUFFER = 1e16; // 1%

    /// @notice Max Fee percentage in basis points (10%)
    uint256 private constant MAX_YIELD_FEE = 10e16;

    /// @notice Implementation contract for creating individual user proxies
    address public immutable i_userProxyImplementation;

    /////////////////////////
    // Storage

    mapping(address user => LeveragePosition[]) private s_userLeveragePositions;

    /// @notice Treasury address to receive fees
    address private s_treasury;

    /// @notice Performance based yield fees on the effective yield generated
    uint256 private s_yieldFee;

    /// @notice Flag to enable user direct control of their proxies
    bool public recoveryMode;

    /////////////////////////
    // Events

    event LeveragePositionOpened(
        address indexed user,
        uint256 indexed positionId,
        uint256 indexed amountDepositedInLoanToken
    );

    event LeveragePositionClosed(
        address indexed user,
        uint256 indexed positionId,
        uint256 indexed amountReturnedInLoanToken
    );

    /////////////////////////
    // Modifiers

    /**
     * @dev Validates if the onBehalfOf address is not a zero address
     * @param onBehalfOf onBehalfOf address
     *
     * Reverts if the onBehalfOf address is a zero address
     */
    modifier validateOnBehalfOf(address onBehalfOf) {
        require(
            onBehalfOf != address(0),
            FLError.FlashLeverage__CannotBeZeroAddress()
        );
        _;
    }

    /// @notice Validates that the collateral token is supported for leveraging.
    /// @dev Checks if a market exists for the collateral-loan token pair.
    /// @param collateralToken The address of the collateral token to validate.
    /// @param loanToken The address of the loan token to validate against.
    modifier validateCollateralToken(
        address collateralToken,
        address loanToken
    ) {
        require(
            isSupportedCollateralToken(collateralToken, loanToken),
            FLError.FlashLeverage__UnsupportedCollateralToken()
        );
        _;
    }

    /**
     * @notice Validates that the provided amount is greater than zero
     * @param value The amount to validate
     */
    modifier validateAmount(uint256 value) {
        require(value > 0, FLError.FlashLeverage__AmountCannotBeZero());
        _;
    }

    /// @notice Validates that the desired LTV does not exceed the maximum allowed LTV for the market.
    /// @dev Prevents positions that would be immediately liquidatable or unsafe.
    /// @param desiredLtv The desired loan-to-value ratio to validate.
    /// @param collateralToken The address of the collateral token.
    /// @param loanToken The address of the loan token.
    modifier validateDesiredLtv(
        uint256 desiredLtv,
        address collateralToken,
        address loanToken
    ) {
        require(
            desiredLtv <= getMaxLtv(collateralToken, loanToken),
            FLError.FlashLeverage__ExceedsMaxLTV()
        );
        _;
    }

    /**
     * @notice Initializes the FlashLeverage contract.
     * @param morphoAddress Address of the Morpho protocol contract.
     * @param swapRouter Address of the Pendle router for swap execution.
     */
    constructor(
        address morphoAddress,
        address swapRouter
    )
        Ownable(msg.sender)
        SwapManager(swapRouter)
        MarketPositionManager(morphoAddress)
    {
        if (morphoAddress == address(0) || swapRouter == address(0)) {
            revert FLError.FlashLeverage__CannotBeZeroAddress();
        }

        // Deploy the implementation contract to clone user proxies from
        i_userProxyImplementation = address(
            new UserProxy(address(this), morphoAddress)
        );
    }

    /////////////////////////
    // External Functions

    function swapAndLeverage() external {}

    function leverage() public {}

    function deleverage() external {}

    /**
     * @notice Creates a new user proxy for each position that user creates
     * @dev Uses the clone factory pattern to create minimal proxy contracts for gas efficiency.
     * This function is permissionless and can be safely called by anyone.
     * @param user The address of the user to get or create a proxy for.
     * @return proxy The address of the user's proxy contract.
     */
    function createUserProxy(address user) public returns (address proxy) {
        proxy = Clones.clone(i_userProxyImplementation);
        UserProxy(proxy).initialize(user);
    }

    /**
     * @notice Allows owner to add support for new collateral tokens.
     * @param tokenConfigs Array of token configurations including swap and market parameters.
     */
    function addSupportedCollateralTokens(
        CollateralTokenConfig[] calldata tokenConfigs
    ) external onlyOwner {
        for (uint256 i; i < tokenConfigs.length; ++i) {
            CollateralTokenConfig memory config = tokenConfigs[i];
            address collateralToken = config.collateralToken;

            // Zero Address check
            require(
                collateralToken != address(0),
                FLError.FlashLeverage__CannotBeZeroAddress()
            );

            // Morpho market check
            MarketParams memory marketParams = i_morpho.idToMarketParams(
                Id.wrap(config.morphoMarketId)
            );
            require(
                collateralToken == marketParams.collateralToken,
                FLError.FlashLeverage__InvalidCollateralToken()
            );

            // Token Decimal check (only tokens with 18 decimals)
            require(
                IERC20Metadata(collateralToken).decimals() ==
                    Math.STANDARD_DECIMALS,
                FLError.FlashLeverage__InvalidCollateralTokenDecimals()
            );

            // Swap Router Check (if the swap router supports swapping of the token)

            _updateMarketParams(marketParams);
            // Provide any params to the swap router if needed
        }
    }

    /**
     * @notice Updates the treasury address
     * @param newTreasury The new treasury address
     * @dev Only callable by the contract owner. Validates that the new treasury is not zero address.
     */
    function updateTreasury(address newTreasury) external onlyOwner {
        require(
            newTreasury != address(0),
            FLError.FlashLeverage__CannotBeZeroAddress()
        );

        s_treasury = newTreasury;
    }

    /**
     * @notice Updates the protocol yield fee.
     * @param newYieldFee The new yield fee to be set in basis points of 1e18 precision.
     * @dev Can only be called by the contract owner.
     *      Reverts if the new fee is zero or exceeds `MAX_YIELD_FEE`.
     */
    function updateYieldFee(uint256 newYieldFee) external onlyOwner {
        require(
            newYieldFee != 0 && newYieldFee <= MAX_YIELD_FEE,
            FLError.FlashLeverage__InvalidYieldFee()
        );

        s_yieldFee = newYieldFee;
    }

    /**
     * @notice Recovers any ERC20 tokens accidentally sent to this contract
     * @param token The address of the token to recover
     */
    function recover(address token) external onlyOwner {
        _transferOut(token, msg.sender, _selfBalance(token));
    }

    /// @notice onlyOwner
    function setRecoveryMode(bool _enabled) external onlyOwner {
        recoveryMode = _enabled;
    }

    /**
     * @notice Overrides renounceOwnership to prevent ownership renunciation.
     * @dev Intentionally disabled to retain upgradeability and collateral support management.
     */
    function renounceOwnership() public override(Ownable) {}

    /////////////////////////
    // Internal Functions

    function _handleLeverage(
        uint256 amountLoan,
        bytes calldata data
    ) internal override nonReentrant {}

    function _handleDeleverage(
        uint256 amountLoan,
        bytes calldata data
    ) internal override nonReentrant {}

    function _revertIfEffectiveLtvTooHigh(
        uint256 desiredLtv,
        address collateralToken,
        address loanToken,
        uint256 amountCollateral,
        uint256 amountLoan
    ) internal view {}

    /////////////////////////
    // Public and External View Functions

    function calcLeverageFlashLoan() public {}

    function calcDeleverageFlashLoan() public {}

    /**
     * @notice Checks if a collateral-loan token pair is supported for leverage operations
     * @param collateralToken The address of the collateral token to validate
     * @param loanToken The address of the loan token to validate
     * @return bool True if the token pair is supported, false otherwise
     * @dev Validates support by checking if market parameters exist for the token pair.
     *      A non-zero collateralToken address in the market parameters indicates the pair
     *      has been configured and is available for leverage operations.
     */
    function isSupportedCollateralToken(
        address collateralToken,
        address loanToken
    ) public view returns (bool) {
        return
            s_marketParams[collateralToken][loanToken].collateralToken !=
            address(0);
    }

    /**
     * @notice Returns all leverage positions for a specific user.
     * @param user The address of the user.
     * @return positions Array of leverage positions.
     */
    function getUserLeveragePositions(
        address user
    ) public view returns (LeveragePosition[] memory) {
        return s_userLeveragePositions[user];
    }

    /**
     * @notice Returns a specific leverage position for a user.
     * @param user Address of the user
     * @param positionId Id of the leverage position
     * @return position The leverage position struct
     */
    function getUserLeveragePosition(
        address user,
        uint256 positionId
    ) public view returns (LeveragePosition memory) {
        return s_userLeveragePositions[user][positionId];
    }

    /**
     * @notice Returns the liquidation loan-to-value ratio for a given collateral-loan token pair.
     * @dev This is the maximum LTV before a position becomes liquidatable.
     * @param collateralToken Address of the collateral token.
     * @param loanToken Address of the loan token.
     * @return liqLtv Liquidation loan-to-value ratio (18 decimals).
     */
    function getLiqLtv(
        address collateralToken,
        address loanToken
    ) public view returns (uint256) {
        return s_marketParams[collateralToken][loanToken].lltv;
    }

    /**
     * @notice Returns the max loan-to-value ratio after applying the liquidation buffer.
     * @param collateralToken Address of the collateral token.
     * @param loanToken Address of the loan token.
     * @return maxLtv Max loan-to-value ratio (18 decimals).
     */
    function getMaxLtv(
        address collateralToken,
        address loanToken
    ) public view returns (uint256) {
        return getLiqLtv(collateralToken, loanToken) - LIQUIDATION_BUFFER;
    }

    /**
     * @notice Returns the current treasury address
     * @return treasury The address of the current treasury
     */
    function getTreasury() public view returns (address) {
        return s_treasury;
    }

    /**
     * @notice Returns the current yield fee configured in the protocol.
     * @return yieldFee The yield fee is a percentage value expressed in basis points
     */
    function getYieldFee() public view returns (uint256) {
        return s_yieldFee;
    }
}
