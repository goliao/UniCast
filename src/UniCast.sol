// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {IVolatilityOracle} from "./interface/IVolatilityOracle.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import "forge-std/console.sol";

contract UniCast {
    using LPFeeLibrary for uint24;
    event VolEvent(uint256 value);

    IVolatilityOracle public volatilityOracle;

    // The default base fees we will charge
    uint24 public constant BASE_FEE = 500; // 0.05%

    error MustUseDynamicFee();

    function getVolatilityOracle() external view returns (address) {
        return address(volatilityOracle);
    }

    function getFee() public view returns (uint24) {
        uint24 volatility = volatilityOracle.getVolatility();
        return BASE_FEE * volatility / 100;
    }
}
