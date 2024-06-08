// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {BaseHook} from "v4-periphery/BaseHook.sol";
import {UniswapV4ERC20} from "v4-periphery/libraries/UniswapV4ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {FixedPoint96} from "v4-core/libraries/FixedPoint96.sol";
import {LiquidityAmounts} from "v4-periphery/libraries/LiquidityAmounts.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "forge-std/console.sol";

contract Vault is BaseHook {
    using LPFeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using SafeCast for uint256;
    using SafeCast for uint128;
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;
    
    error MustUseDynamicFee();
    event LiquidityAdded(uint256 amount0, uint256 amount1);
    event LiquidityRemoved(uint256 amount0, uint256 amount1);

    error PoolNotInitialized();
    error InsufficientInitialLiquidity();
    error SenderMustBeHook();
    error TooMuchSlippage();
    error LiquidityDoesntMeetMinimum();

    int256 internal constant MAX_INT = type(int256).max;
    uint16 internal constant MINIMUM_LIQUIDITY = 1000;
    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;
    bytes internal constant ZERO_BYTES = "";
    bool poolRebalancing;

    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.ModifyLiquidityParams params;
    }

    struct PoolInfo {
        bool hasAccruedFees;
        UniswapV4ERC20 poolToken;
    }

    mapping(PoolId => PoolInfo) public poolInfos;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
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
        address,
        PoolKey calldata key,
        uint160,
        bytes calldata
    ) external override poolManagerOnly returns (bytes4) {
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
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external view override returns (bytes4) {
        if (sender != address(this)) revert SenderMustBeHook();

        return Vault.beforeAddLiquidity.selector;
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = key.toId();

        if (!poolInfos[poolId].hasAccruedFees) {
            PoolInfo storage pool = poolInfos[poolId];
            pool.hasAccruedFees = true;
        }

        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(
        address,
        PoolKey calldata poolKey,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external virtual override poolManagerOnly returns (bytes4, int128) {
        PoolId poolId = poolKey.toId();
        PoolInfo storage poolInfo = poolInfos[poolId];

        poolInfo.hasAccruedFees = true;

        autoRebalance(poolKey);

        return (IHooks.afterSwap.selector, 0);
    }

    function addLiquidity(PoolKey memory poolKey, uint256 amount0, uint256 amount1) 
        external 
        returns (uint128 liquidity)
    {
        PoolId poolId = poolKey.toId();

        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);

        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        uint128 poolLiquidity = poolManager.getLiquidity(poolId);

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(MIN_TICK),
            TickMath.getSqrtPriceAtTick(MAX_TICK),
            amount0,
            amount1
        );

        if (poolLiquidity == 0 && liquidity <= MINIMUM_LIQUIDITY) {
            revert LiquidityDoesntMeetMinimum();
        }

        (BalanceDelta addedDelta, ) = poolManager.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                liquidityDelta: liquidity.toInt256(),
                salt: 0
            }),
            ZERO_BYTES
        );

        if (poolLiquidity == 0) {
            liquidity -= MINIMUM_LIQUIDITY;
            UniswapV4ERC20(poolInfos[poolId].poolToken).mint(address(0), MINIMUM_LIQUIDITY);
        }

        UniswapV4ERC20(poolInfos[poolId].poolToken).mint(msg.sender, liquidity);

        if (uint128(-addedDelta.amount0()) < amount0 || uint128(-addedDelta.amount1()) < amount1) {
            revert TooMuchSlippage();
        }

        emit LiquidityAdded(amount0, amount1);
    }

    function removeLiquidity(PoolKey memory poolKey, uint256 amount0, uint256 amount1)
        external 
    {
        PoolId poolId = poolKey.toId();

        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);

        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        uint256 liquidityToRemove = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(MIN_TICK),
            TickMath.getSqrtPriceAtTick(MAX_TICK),
            amount0,
            amount1
        );

        (BalanceDelta delta, ) = poolManager.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                liquidityDelta: -(liquidityToRemove.toInt256()),
                salt: 0
            }),
            ZERO_BYTES
        );

        UniswapV4ERC20(poolInfos[poolId].poolToken).burn(msg.sender, uint256(liquidityToRemove));

        if (uint128(-delta.amount0()) < amount0 || uint128(-delta.amount1()) < amount1) {
            revert TooMuchSlippage();
        }

        emit LiquidityRemoved(amount0, amount1);
    }

    function autoRebalance(PoolKey memory poolKey) public {
        PoolId poolId = poolKey.toId();
        PoolInfo storage poolInfo = poolInfos[poolId];

        if (rebalanceRequired(poolKey)) {
            poolRebalancing = true;
            _rebalance(poolKey);
            poolRebalancing = false;
            poolInfo.hasAccruedFees = true;
        }
    }

    function rebalanceRequired(PoolKey memory poolKey) public view returns (bool) {
        PoolId poolId = poolKey.toId();
        PoolInfo storage poolInfo = poolInfos[poolId];
        (, int24 currentTick,, ) = poolManager.getSlot0(poolId);

        // TODO: define rebalance conditions
        return true;
    }

    function unlockCallback(bytes calldata rawData)
        external
        override
        returns (bytes memory)
    {
        CallbackData memory data = abi.decode(rawData, (CallbackData));
        BalanceDelta delta;

        if (data.params.liquidityDelta < 0) {
            delta = _removeLiquidity(data.key, data.params);
            _takeDeltas(data.sender, data.key, delta);
        } else {
            (delta,) = poolManager.modifyLiquidity(data.key, data.params, ZERO_BYTES);
            _settleDeltas(data.sender, data.key, delta);
        }
        return abi.encode(delta);
    }

    function _settleDeltas(address sender, PoolKey memory key, BalanceDelta delta) internal {
        if (sender == address(this)) {
            key.currency0.transfer(address(poolManager), uint256(int256(-delta.amount0())));
            key.currency1.transfer(address(poolManager), uint256(int256(-delta.amount1())));
        } else {
            IERC20(Currency.unwrap(key.currency0)).safeTransferFrom(
                sender,
                address(poolManager),
                uint256(int256(-delta.amount0()))
            );
            IERC20(Currency.unwrap(key.currency1)).safeTransferFrom(
                sender,
                address(poolManager),
                uint256(int256(-delta.amount1()))
            );
        }
        poolManager.settle(key.currency0);
        poolManager.settle(key.currency1);
    }

    function _takeDeltas(address sender, PoolKey memory key, BalanceDelta delta) internal {
        poolManager.take(key.currency0, sender, uint256(uint128(delta.amount0())));
        poolManager.take(key.currency1, sender, uint256(uint128(delta.amount1())));
    }

    function _removeLiquidity(PoolKey memory key, IPoolManager.ModifyLiquidityParams memory params)
        internal
        returns (BalanceDelta delta)
    {
        PoolId poolId = key.toId();
        PoolInfo storage pool = poolInfos[poolId];

        if (pool.hasAccruedFees) {
            _rebalance(key);
        }

        uint256 liquidityToRemove = FullMath.mulDiv(
            uint256(-params.liquidityDelta),
            poolManager.getLiquidity(poolId),
            UniswapV4ERC20(pool.poolToken).totalSupply()
        );

        params.liquidityDelta = -(liquidityToRemove.toInt256());
        (delta,) = poolManager.modifyLiquidity(key, params, ZERO_BYTES);
        pool.hasAccruedFees = false;
    }

    function _rebalance(PoolKey memory key) public {
        PoolId poolId = key.toId();
        (BalanceDelta balanceDelta,) = poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                liquidityDelta: -(poolManager.getLiquidity(poolId).toInt256()),
                salt: 0
            }),
            ZERO_BYTES
        );

        uint160 newSqrtPriceX96 = (
            FixedPointMathLib.sqrt(
                FullMath.mulDiv(uint128(balanceDelta.amount1()), FixedPoint96.Q96, uint128(balanceDelta.amount0()))
            ) * FixedPointMathLib.sqrt(FixedPoint96.Q96)
        ).toUint160();

        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);

        poolManager.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: newSqrtPriceX96 < sqrtPriceX96,
                amountSpecified: -MAX_INT - 1, // equivalent of type(int256).min
                sqrtPriceLimitX96: newSqrtPriceX96
            }),
            ZERO_BYTES
        );

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            newSqrtPriceX96,
            TickMath.getSqrtPriceAtTick(MIN_TICK),
            TickMath.getSqrtPriceAtTick(MAX_TICK),
            uint256(uint128(balanceDelta.amount0())),
            uint256(uint128(balanceDelta.amount1()))
        );

        (BalanceDelta balanceDeltaAfter,) = poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                liquidityDelta: liquidity.toInt256(),
                salt: 0
            }),
            ZERO_BYTES
        );

        uint128 donateAmount0 = uint128(balanceDelta.amount0() + balanceDeltaAfter.amount0());
        uint128 donateAmount1 = uint128(balanceDelta.amount1() + balanceDeltaAfter.amount1());

        poolManager.donate(key, donateAmount0, donateAmount1, ZERO_BYTES);
    }
}