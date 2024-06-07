// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import "forge-std/console.sol";

contract UniCast is BaseHook {
    using LPFeeLibrary for uint24;
    event VolEvent(uint256 value);

    uint128 public impliedVol;
    
    // The default base fees we will charge
    uint24 public constant BASE_FEE = 500; // 0.05%

    error MustUseDynamicFee();

    // Initialize BaseHook parent contract in the constructor
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        
    }

    // Required override function for BaseHook to let the PoolManager know which hooks are implemented
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function beforeInitialize(
        address,
        PoolKey calldata key,
        uint160,
        bytes calldata
    ) external override returns (bytes4) {
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        impliedVol=20;
        return this.beforeInitialize.selector;
    }

    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        bytes calldata
    ) external override poolManagerOnly returns (bytes4, BeforeSwapDelta, uint24) {
        uint24 fee = getFee();
        poolManager.updateDynamicLPFee(key, fee);
        return (this.beforeSwap.selector,  BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }


    function getFee() public returns (uint24) {

        // TODO: replace with event implied vol feed
        if (block.number == 12355) {
            console.log("High vol event at block", block.number); // Log message
            impliedVol=40;
            emit VolEvent(impliedVol);
        }

        if (impliedVol > 20) {
            return uint24(BASE_FEE * impliedVol/20);
        }

        return BASE_FEE;
    }


}
