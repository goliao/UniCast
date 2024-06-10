// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {IUniCastOracle, LiquidityData} from "./interface/IUniCastOracle.sol";

contract UniCastOracle is Ownable, IUniCastOracle {
    uint24 public impliedVol;
    address public keeper;
    
    event KeeperUpdated(address indexed newKeeper);
    event VolEvent(uint256 value);

    error Unauthorized();

    mapping (PoolId => LiquidityData) public liquidityData;

    modifier onlyKeeper() {
        if (msg.sender != keeper) revert Unauthorized();
        _;
    }

    /**
     * @dev Constructor to initialize the UniCastOracle contract.
     * @param _keeper The address of the initial keeper.
     */
    constructor(address _keeper) Ownable(_keeper) {
        keeper = _keeper;
        impliedVol = 100;
    }

    /**
     * @dev Sets the liquidity data for a given pool.
     * @param _poolId The ID of the pool.
     * @param _tickLower The lower tick boundary.
     * @param _tickUpper The upper tick boundary.
     * @param _liquidityDelta The change in liquidity.
     */
    function setLiquidityData(PoolId _poolId, int24 _tickLower, int24 _tickUpper, int256 _liquidityDelta) external onlyKeeper {
        liquidityData[_poolId] = LiquidityData({
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            liquidityDelta: _liquidityDelta
        });
    }

    /**
     * @dev Gets the liquidity data for a given pool.
     * @param _poolId The ID of the pool.
     * @return The liquidity data of the pool.
     */
    function getLiquidityData(PoolId _poolId) external view returns (LiquidityData memory) {
        return liquidityData[_poolId];
    }

    /**
     * @dev Sets the implied volatility.
     * @param _impliedVol The new implied volatility.
     */
    function setImpliedVol(uint24 _impliedVol) external onlyKeeper {
        impliedVol = _impliedVol;
        emit VolEvent(impliedVol);
    }

    /**
     * @dev Updates the keeper address.
     * @param _newKeeper The address of the new keeper.
     */
    function updateKeeper(address _newKeeper) external onlyKeeper {
        keeper = _newKeeper;
        emit KeeperUpdated(_newKeeper);
    }

    /**
     * @dev Gets the current implied volatility.
     * @return The current implied volatility.
     */
    function getVolatility() external view override returns (uint24) {
        return impliedVol;
    }
}
