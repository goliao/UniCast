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

abstract contract UniCastVolitilityFee is BaseHook {
    using LPFeeLibrary for uint24;

    event VolEvent(uint256 value);

    error MustUseDynamicFee();

    IUniCastOracle public volitilityOracle;
    IPoolManager public poolManagerFee;

    // The default base fees we will charge
    uint24 public constant BASE_FEE = 500; // 0.05%

    constructor(IPoolManager _poolManager, IUniCastOracle _oracle) {
        poolManagerFee = _poolManager;
        volitilityOracle = _oracle;
    }

    function getHookPermissions()
        public
        pure
        virtual
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
    ) external virtual override returns (bytes4) {
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        // impliedVol=20;
        return this.beforeInitialize.selector;
    }

    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        bytes calldata
    )
        external
        override
        virtual
        poolManagerOnly
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint24 fee = getFee();
        poolManagerFee.updateDynamicLPFee(key, fee);

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function getVolatilityOracle() external view returns (address) {
        return address(volitilityOracle);
    }

    function getFee() public view returns (uint24) {
        uint24 volatility = volitilityOracle.getVolatility();
        return BASE_FEE * volatility / 100;
    }
}
