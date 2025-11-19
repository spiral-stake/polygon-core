// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @title CollateralTokenConfig
 * @dev Configuration contract for collateral token settings
 * @notice Contains all collateral token configurations for the Flash Leverage system
 */
contract CollateralTokenConfig {
    /**
     * @dev Returns all collateral token configurations
     * @return collateralTokens Array of supported collateral tokens
     * @return morphoMarketIds Array of morphoMarketIds of the collateralTokens
     */
    function getTokenConfigs()
        external
        pure
        returns (
            address[] memory collateralTokens,
            bytes32[] memory morphoMarketIds
        )
    {
        collateralTokens = new address[](1);
        morphoMarketIds = new bytes32[](1);

        // wstETH
        collateralTokens[0] = 0x03b54A6e9a984069379fae1a4fC4dBAE93B3bCCD;
        morphoMarketIds[
            0
        ] = 0xb8ae474af3b91c8143303723618b31683b52e9c86566aa54c06f0bc27906bcae;
    }

    function getTokenWhales()
        external
        pure
        returns (address[] memory tokenWhales)
    {
        tokenWhales = new address[](1);

        tokenWhales[0] = 0x3aEA6b209321493942AbADAE01c020400ba20C3C; // wstETH
    }
}
