// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks, IHooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {RebalancingUniCastHook} from "../../src/RebalancingUniCastHook.sol";
import {IVolatilityOracle} from "../../src/interface/IVolatilityOracle.sol";

contract UniCastImplementation is RebalancingUniCastHook {
    constructor(IPoolManager _poolManager) RebalancingUniCastHook(_poolManager) {
    }

    // make this a no-op in testing
    function validateHookAddress(BaseHook _this) internal pure override {}
}
