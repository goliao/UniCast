// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {IUniCastOracle} from "./interface/IUniCastOracle.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import "forge-std/console.sol";

abstract contract UniCastVolitilityFee {
    using LPFeeLibrary for uint24;

    event VolEvent(uint256 value);

    error MustUseDynamicFee();

    IUniCastOracle public volitilityOracle;
    IPoolManager public poolManagerFee;

    // The default base fees we will charge
    uint24 public constant BASE_FEE = 500; // 0.05%

    /**
     * @dev Constructor for the UniCastVolitilityFee contract.
     * @param _poolManager The address of the pool manager.
     * @param _oracle The address of the volatility oracle.
     */
    constructor(IPoolManager _poolManager, IUniCastOracle _oracle) {
        poolManagerFee = _poolManager;
        volitilityOracle = _oracle;
    }

    /**
     * @dev Returns the address of the volatility oracle.
     * @return The address of the volatility oracle.
     */
    function getVolatilityOracle() external view returns (address) {
        return address(volitilityOracle);
    }

    /**
     * @dev Calculates and returns the fee based on the current volatility.
     * @return The calculated fee as a uint24.
     */
    function getFee() public view returns (uint24) {
        uint24 volatility = volitilityOracle.getVolatility();
        return BASE_FEE * volatility / 100;
    }
}
