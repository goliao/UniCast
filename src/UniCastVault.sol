// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {UniswapV4ERC20} from "v4-periphery/libraries/UniswapV4ERC20.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {FixedPoint96} from "v4-core/libraries/FixedPoint96.sol";
import {LiquidityAmounts} from "v4-periphery/libraries/LiquidityAmounts.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TransientStateLibrary} from "v4-core/libraries/TransientStateLibrary.sol";
import {IUniCastOracle, LiquidityData} from "./interface/IUniCastOracle.sol";

abstract contract UniCastVault {
    using LPFeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using SafeCast for uint256;
    using SafeCast for uint128;
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;
    
    event LiquidityAdded(uint256 amount0, uint256 amount1);
    event LiquidityRemoved(uint256 amount0, uint256 amount1);

    error PoolNotInitialized();
    error InsufficientInitialLiquidity();
    error SenderMustBeHook();
    error TooMuchSlippage();
    error LiquidityDoesntMeetMinimum();

    int256 internal constant MAX_INT = type(int256).max;
    uint16 internal constant MINIMUM_LIQUIDITY = 1000;
    int24 internal constant MIN_TICK = -887220;
    int24 internal constant MAX_TICK = -MIN_TICK;
    bytes internal constant ZERO_BYTES = "";
    bool poolRebalancing;

    IPoolManager public immutable poolManagerVault;
    IUniCastOracle public liquidityOracle;

    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.ModifyLiquidityParams params;
        bytes hookData;
        bool settleUsingBurn;
        bool takeClaims;
    }

    struct PoolInfo {
        bool hasAccruedFees;
        UniswapV4ERC20 poolToken;
    }

    mapping(PoolId => PoolInfo) public poolInfos;

    constructor(IPoolManager _poolManager, IUniCastOracle _oracle) {
        poolManagerVault = _poolManager;
        liquidityOracle = _oracle;
    } 

    /**
     * @notice Adds liquidity to the pool.
     * @param poolKey The key of the pool.
     * @param amount0 The amount of token0 to add.
     * @param amount1 The amount of token1 to add.
     * @return liquidity The amount of liquidity added.
     */
    function addLiquidity(PoolKey memory poolKey, uint256 amount0, uint256 amount1) 
        external 
        returns (uint128 liquidity)
    {
        PoolId poolId = poolKey.toId();

        (uint160 sqrtPriceX96,,,) = poolManagerVault.getSlot0(poolId);

        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        uint128 poolLiquidity = poolManagerVault.getLiquidity(poolId);

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

        (BalanceDelta addedDelta, ) = modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                liquidityDelta: liquidity.toInt256(),
                salt: 0
            }),
            ZERO_BYTES,
            false,
            false
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

    /**
     * @notice Removes liquidity from the pool.
     * @param poolKey The key of the pool.
     * @param amount0 The amount of token0 to remove.
     * @param amount1 The amount of token1 to remove.
     */
    function removeLiquidity(PoolKey memory poolKey, uint256 amount0, uint256 amount1)
        external 
    {
        PoolId poolId = poolKey.toId();

        (uint160 sqrtPriceX96,,,) = poolManagerVault.getSlot0(poolId);

        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        uint256 liquidityToRemove = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(MIN_TICK),
            TickMath.getSqrtPriceAtTick(MAX_TICK),
            amount0,
            amount1
        );

        (BalanceDelta delta, ) = modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                liquidityDelta: -(liquidityToRemove.toInt256()),
                salt: 0
            }),
            ZERO_BYTES,
            true,
            false
        );

        UniswapV4ERC20(poolInfos[poolId].poolToken).burn(msg.sender, uint256(liquidityToRemove));

        if (uint128(-delta.amount0()) < amount0 || uint128(-delta.amount1()) < amount1) {
            revert TooMuchSlippage();
        }

        emit LiquidityRemoved(amount0, amount1);
    }

    /**
     * @notice Automatically rebalances the pool if required.
     * @param poolKey The key of the pool.
     */
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

    /**
     * @notice Checks if rebalancing is required for the pool.
     * @param poolKey The key of the pool.
     * @return bool True if rebalancing is required, false otherwise.
     */
    function rebalanceRequired(PoolKey memory poolKey) public view returns (bool) {
        PoolId poolId = poolKey.toId();
        PoolInfo storage poolInfo = poolInfos[poolId];
        (, int24 currentTick,, ) = poolManagerVault.getSlot0(poolId);

        LiquidityData memory liquidityData = liquidityOracle.getLiquidityData(poolId);
        return true;
    }

    /**
     * @notice Modifies the liquidity of the pool.
     * @param poolKey The key of the pool.
     * @param params The parameters for modifying liquidity.
     * @param hookData Additional data for the hook.
     * @param settleUsingBurn Whether to settle using burn.
     * @param takeClaims Whether to take claims.
     * @return delta The balance delta after modification.
     * @return uint256 The ETH balance of the contract.
     */
    function modifyLiquidity(
        PoolKey memory poolKey,
        IPoolManager.ModifyLiquidityParams memory params,
        bytes memory hookData,
        bool settleUsingBurn,
        bool takeClaims
    ) internal returns (BalanceDelta delta, uint256) {
        delta = abi.decode(
            poolManagerVault.unlock(abi.encode(CallbackData(msg.sender, poolKey, params, hookData, settleUsingBurn, takeClaims))),
            (BalanceDelta)
            );
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    /**
     * @notice Callback function for unlocking the vault.
     * @param rawData The raw data for the callback.
     * @return bytes The encoded balance delta.
     */
    function _unlockVaultCallback(bytes calldata rawData)
        internal
        virtual
        returns (bytes memory)
    {
        require(msg.sender == address(poolManagerVault), "Callback not called by manager");
        
        CallbackData memory data = abi.decode(rawData, (CallbackData));
        BalanceDelta delta;
        PoolInfo storage poolInfo = poolInfos[data.key.toId()];

        if (data.params.liquidityDelta < 0) {
            delta = _modifyLiquidity(data);
            poolInfo.hasAccruedFees = false;
        } else {
            (delta,) = poolManagerVault.modifyLiquidity(data.key, data.params, ZERO_BYTES);
            _settleDeltas(data.sender, data.key, delta);
        }
        return abi.encode(delta);
    }

    /**
     * @notice Modifies the liquidity based on the callback data.
     * @param modifierData The callback data for modifying liquidity.
     * @return delta The balance delta after modification.
     */
    function _modifyLiquidity(CallbackData memory modifierData)
        internal
        returns (BalanceDelta delta)
    {
        uint128 liquidityBefore = poolManagerVault.getPosition(
            modifierData.key.toId(),
            address(this),
            modifierData.params.tickLower,
            modifierData.params.tickUpper,
            modifierData.params.salt
        ).liquidity;
        (delta,) = poolManagerVault.modifyLiquidity(modifierData.key, modifierData.params, modifierData.hookData);
        uint128 liquidityAfter = poolManagerVault.getPosition(
            modifierData.key.toId(),
            address(this),
            modifierData.params.tickLower,
            modifierData.params.tickUpper,
            modifierData.params.salt
        ).liquidity;

        (,, int256 delta0) = _fetchBalances(modifierData.key.currency0, modifierData.sender, address(this));
        (,, int256 delta1) = _fetchBalances(modifierData.key.currency1, modifierData.sender, address(this));

        require( 
            int128(liquidityAfter) == 
            int128(liquidityBefore) + modifierData.params.liquidityDelta, 
            "Incorrect liquidity after adding" );

        if (delta0 != 0) {
            if (delta0 < 0) {
                _settle(modifierData.key.currency0, poolManagerVault, modifierData.sender, uint256(-delta0), modifierData.settleUsingBurn);
            } else {
                _take(modifierData.key.currency0, poolManagerVault, modifierData.sender, uint256(delta0), modifierData.takeClaims);
            }
        }

        if (delta1 != 0) {
            if (delta1 < 0) {
                _settle(modifierData.key.currency1, poolManagerVault, modifierData.sender, uint256(-delta1), modifierData.settleUsingBurn);
            } else {
                _take(modifierData.key.currency1, poolManagerVault, modifierData.sender, uint256(delta1), modifierData.takeClaims);
            }
        }
    }

    /**
     * @notice Fetches the balances of a user and the pool.
     * @param currency The currency to fetch balances for.
     * @param user The address of the user.
     * @param deltaHolder The address holding the delta.
     * @return userBalance The balance of the user.
     * @return poolBalance The balance of the pool.
     * @return delta The balance delta.
     */
    function _fetchBalances(Currency currency, address user, address deltaHolder)
        internal
        view
        returns (uint256 userBalance, uint256 poolBalance, int256 delta)
    {
        userBalance = currency.balanceOf(user);
        poolBalance = currency.balanceOf(address(poolManagerVault));
        delta = poolManagerVault.currencyDelta(deltaHolder, currency);
    }

    /**
     * @notice Settles the deltas for a given sender and pool key.
     * @param sender The address of the sender.
     * @param key The key of the pool.
     * @param delta The balance delta to settle.
     */
    function _settleDeltas(address sender, PoolKey memory key, BalanceDelta delta) internal {
        _settle(key.currency0, poolManagerVault, sender, uint256(int256(-delta.amount0())), false);
        _settle(key.currency1, poolManagerVault, sender, uint256(int256(-delta.amount1())), false);
    }

    /**
     * @notice Settles a given amount of currency.
     * @param currency The currency to settle.
     * @param manager The pool manager.
     * @param payer The address of the payer.
     * @param amount The amount to settle.
     * @param burn Whether to burn the amount.
     */
    function _settle(Currency currency, IPoolManager manager, address payer, uint256 amount, bool burn) internal {
        if (burn) {
            poolManagerVault.burn(payer, currency.toId(), amount);
        } else if (currency.isNative()) {
            poolManagerVault.settle{value: amount}(currency);
        } else {
            poolManagerVault.sync(currency);
            if (payer != address(this)) {
                IERC20(Currency.unwrap(currency)).transferFrom(payer, address(poolManagerVault), amount);
            } else {
                IERC20(Currency.unwrap(currency)).transfer(address(poolManagerVault), amount);
            }
            poolManagerVault.settle(currency);
        }
    }
    
    /**
     * @notice Takes a given amount of currency.
     * @param currency The currency to take.
     * @param manager The pool manager.
     * @param recipient The address of the recipient.
     * @param amount The amount to take.
     * @param claims Whether to take claims.
     */
    function _take(Currency currency, IPoolManager manager, address recipient, uint256 amount, bool claims) internal {
        if (claims) {
            poolManagerVault.mint(recipient, currency.toId(), amount);
        } else {
            poolManagerVault.take(currency, recipient, amount);
        }
    }

    /**
     * @notice Rebalances the pool.
     * @param key The key of the pool.
     */
    function _rebalance(PoolKey memory key) 
        internal 
    {
        PoolId poolId = key.toId();
        (BalanceDelta balanceDelta,) = poolManagerVault.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                liquidityDelta: -(poolManagerVault.getLiquidity(poolId).toInt256()),
                salt: 0
            }),
            ZERO_BYTES
        );

        uint160 newSqrtPriceX96 = (
            FixedPointMathLib.sqrt(
                FullMath.mulDiv(uint128(balanceDelta.amount1()), FixedPoint96.Q96, uint128(balanceDelta.amount0()))
            ) * FixedPointMathLib.sqrt(FixedPoint96.Q96)
        ).toUint160();

        (uint160 sqrtPriceX96,,,) = poolManagerVault.getSlot0(poolId);

        poolManagerVault.swap(
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

        (BalanceDelta balanceDeltaAfter,) = poolManagerVault.modifyLiquidity(
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

        poolManagerVault.donate(key, donateAmount0, donateAmount1, ZERO_BYTES);
    }
}