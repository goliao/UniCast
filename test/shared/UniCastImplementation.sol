// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks, IHooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {UniCastHook} from "../../src/UniCastHook.sol";
import {IUniCastOracle} from "../../src/interface/IUniCastOracle.sol";

contract UniCastImplementation is UniCastHook {
    constructor(IPoolManager _poolManager, IUniCastOracle _oracle, UniCastHook addressToEtch) UniCastHook(_poolManager, _oracle) {
        Hooks.validateHookPermissions(addressToEtch, getHookPermissions());
    }

    // make this a no-op in testing
    function validateHookAddress(BaseHook _this) internal pure override {}
}
