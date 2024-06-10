// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
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

contract UniCastHook is UniCastVolitilityFee, UniCastVault, BaseHook {
    using LPFeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;

    constructor(
        IPoolManager _poolManager, 
        IUniCastOracle _oracle
    ) 
        UniCastVault(_poolManager, _oracle) 
        UniCastVolitilityFee(_poolManager, _oracle) 
        BaseHook(_poolManager) {}

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
        override
        returns (bytes4) 
    {
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        PoolId poolId = key.toId();
        string memory tokenSymbol = string(
            abi.encodePacked(
                "UniV4",
                "-",
                IERC20Metadata(Currency.unwrap(key.currency0)).symbol(),
                "-",
                IERC20Metadata(Currency.unwrap(key.currency1)).symbol(),
                "-",
                Strings.toString(uint256(key.fee))
            )
        );
        UniswapV4ERC20 poolToken = new UniswapV4ERC20(tokenSymbol, tokenSymbol);
        poolInfos[poolId] = PoolInfo({
            hasAccruedFees: false,
            poolToken: poolToken
        });
        return IHooks.beforeInitialize.selector;
    }

    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata data
    ) 
        external  
        override
        returns (bytes4) 
    {
        if (sender != address(this)) revert SenderMustBeHook();

        return IHooks.beforeAddLiquidity.selector;
    }

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata data
    )
        external
        override
        poolManagerOnly
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint24 fee = getFee();
        if (BASE_FEE < fee) poolManagerFee.updateDynamicLPFee(key, fee);
        PoolId poolId = key.toId();

        if (!poolInfos[poolId].hasAccruedFees) {
            PoolInfo storage pool = poolInfos[poolId];
            pool.hasAccruedFees = true;
        }

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
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
        override
        poolManagerOnly 
        returns (bytes4, int128) 
    {
        PoolId poolId = poolKey.toId();
        PoolInfo storage poolInfo = poolInfos[poolId];

        poolInfo.hasAccruedFees = true;

        autoRebalance(poolKey);

        return (IHooks.afterSwap.selector, 0);
    }

    function unlockCallback(bytes calldata rawData)
        external
        override
        returns (bytes memory)
    {
        return _unlockVaultCallback(rawData);
    }
}
