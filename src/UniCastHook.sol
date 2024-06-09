// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {UniCastVolitilityFee} from "./UniCastVolitilityFee.sol";
import {UniCastVault} from "./UniCastVault.sol";
import {Initializable} from "./Initializable.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {IUniCastOracle} from "./interface/IUniCastOracle.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {UniswapV4ERC20} from "v4-periphery/libraries/UniswapV4ERC20.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

import "forge-std/console.sol";

contract UniCastHook is UniCastVolitilityFee, UniCastVault {
    using LPFeeLibrary for uint24;

    // error MustUseDynamicFee();

    // IUniCastOracle public oracle;

    constructor(IPoolManager _poolManager, IUniCastOracle _oracle) 
        UniCastVault(_poolManager, _oracle) 
        UniCastVolitilityFee(_poolManager, _oracle) 
        BaseHook(_poolManager) {}
        // oracle = oracle;
    // }

    // function initialize(IUniCastOracle oracle, IPoolManager _poolManager) public initializer {
    //     oracle = oracle;
    // }

    // Required override function for BaseHook to let the PoolManager know which hooks are implemented
    function getHookPermissions()
        public
        pure
        override(UniCastVolitilityFee, UniCastVault)
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: true,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function beforeInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        bytes calldata data
    )  
        external 
        override(UniCastVolitilityFee, UniCastVault) 
        returns (bytes4) 
    {
        UniCastVault(address(this)).beforeInitialize(
            sender,
            key,
            sqrtPriceX96,
            data
        );
        UniCastVolitilityFee(address(this)).beforeInitialize(
            sender,
            key,
            sqrtPriceX96,
            data
        );
        return IHooks.beforeInitialize.selector;
    }

    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata data
    ) 
        external  
        override(UniCastVault, BaseHook)
        returns (bytes4) 
    {
        return 
            UniCastVault(address(this)).beforeAddLiquidity(sender, key, params, data);
    }

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata data
    )
        external
        override(UniCastVolitilityFee, UniCastVault)
        poolManagerOnly
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        (bytes4 selector1, BeforeSwapDelta delta1, uint24 fee1) = UniCastVault(address(this)).beforeSwap(sender, key, params, data);
        (bytes4 selector2, BeforeSwapDelta delta2, uint24 fee2) = UniCastVolitilityFee(address(this)).beforeSwap(sender, key, params, data);
        return (IHooks.beforeSwap.selector, delta1, fee1 + fee2); 
    }

    function afterSwap(
        address sender,
        PoolKey calldata poolKey,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata data
    ) 
        external 
        virtual 
        override(UniCastVault, BaseHook)
        poolManagerOnly 
        returns (bytes4, int128) 
    {
        return UniCastVault(address(this)).afterSwap(sender, poolKey, params, delta, data);
    }

    function unlockCallback(bytes calldata rawData)
        external
        override(UniCastVault, BaseHook)
        returns (bytes memory)
    {
        return UniCastVault(address(this)).unlockCallback(rawData);
    }
}
