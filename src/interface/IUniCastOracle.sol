// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;
import {PoolId} from "v4-core/types/PoolId.sol";

/**
 * @dev Struct to hold liquidity data.
 * @param tickLower The lower tick boundary.
 * @param tickUpper The upper tick boundary.
 */
struct LiquidityData {
    int24 tickLower;
    int24 tickUpper;
}

/**
 * @dev Interface for the UniCast Oracle.
 */
interface IUniCastOracle {
    /**
     * @dev Gets the current fee.
     * @param _poolId ID of the pool
     * @return The current fee as a uint24.
     */
    function getFee(PoolId _poolId) external view returns (uint24);

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
     */
    function setLiquidityData(PoolId _poolId, int24 _tickLower, int24 _tickUpper) external;

    /**
     * @dev Sets the fee for a pool.
     * @param _poolId ID of the pool.
     * @param _fee The new fee.
     */
    function setFee(PoolId _poolId, uint24 _fee) external;

    /**
     * @dev Updates the keeper address.
     * @param _newKeeper The address of the new keeper.
     */
    function updateKeeper(address _newKeeper) external;
}