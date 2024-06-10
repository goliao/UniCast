// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import {PoolId} from "v4-core/types/PoolId.sol";

/**
 * @dev Struct to hold liquidity data.
 * @param tickLower The lower tick boundary.
 * @param tickUpper The upper tick boundary.
 * @param liquidityDelta The change in liquidity.
 */
struct LiquidityData {
    int24 tickLower;
    int24 tickUpper;
    int256 liquidityDelta;   
}

/**
 * @dev Interface for the UniCast Oracle.
 */
interface IUniCastOracle {
    /**
     * @dev Gets the current volatility.
     * @return The current volatility as a uint24.
     */
    function getVolatility() external view returns (uint24);

    /**
     * @dev Gets the liquidity data for a given pool.
     * @param _poolId The ID of the pool.
     * @return The liquidity data of the pool.
     */
    function getLiquidityData(PoolId _poolId) external view returns (LiquidityData memory);

    /**
     * @dev Sets the liquidity data for a given pool.
     * @param _poolId The ID of the pool.
     * @param _tickLower The lower tick boundary.
     * @param _tickUpper The upper tick boundary.
     * @param _liquidityDelta The change in liquidity.
     */
    function setLiquidityData(PoolId _poolId, int24 _tickLower, int24 _tickUpper, int256 _liquidityDelta) external;

    /**
     * @dev Sets the implied volatility.
     * @param _impliedVol The new implied volatility.
     */
    function setImpliedVol(uint24 _impliedVol) external;

    /**
     * @dev Updates the keeper address.
     * @param _newKeeper The address of the new keeper.
     */
    function updateKeeper(address _newKeeper) external;
}