// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import {PoolId} from "v4-core/types/PoolId.sol";

struct LiquidityData {
    int24 tickLower;
    int24 tickUpper;
    int256 liquidityDelta;   
}

interface IUniCastOracle {
    function getVolatility() external view returns (uint24);

    function getLiquidityData(PoolId _poolId) external view returns (LiquidityData memory);

    function setLiquidityData(PoolId _poolId, int24 _tickLower, int24 _tickUpper, int256 _liquidityDelta) external;

    function setImpliedVol(uint24 _impliedVol) external;

    function updateKeeper(address _newKeeper) external;
}