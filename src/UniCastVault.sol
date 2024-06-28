// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Position} from "v4-core/libraries/Position.sol";
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
    using FixedPointMathLib for uint256;
    using FullMath for uint256;

    event LiquidityAdded(uint256 amount0, uint256 amount1);
    event LiquidityRemoved(uint256 amount0, uint256 amount1);
    event RebalanceOccurred(
        PoolId poolId,
        int24 oldLowerTick,
        int24 oldUpperTick,
        int24 newLowerTick,
        int24 newUpperTick
    );

    error PoolNotInitialized();
    error InsufficientInitialLiquidity();
    error SenderMustBeHook();
    error TooMuchSlippage();
    error LiquidityDoesntMeetMinimum();

    int256 internal constant MAX_INT = type(int256).max;
    uint16 internal constant MINIMUM_LIQUIDITY = 1000;
    int24 internal minTick; // current active min tick
    int24 internal maxTick; // current active maxTick
    bytes internal constant ZERO_BYTES = "";
    bool poolRebalancing;

    IPoolManager public immutable manager;
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
        UniswapV4ERC20 poolToken;
    }

    mapping(PoolId => UniswapV4ERC20) public vaultLiquidityToken;

    constructor(
        IPoolManager _poolManager,
        IUniCastOracle _oracle,
        int24 initialMinTick,
        int24 initialMaxTick
    ) {
        manager = _poolManager;
        liquidityOracle = _oracle;
        minTick = initialMinTick;
        maxTick = initialMaxTick;
    }

    /**
     * @notice Adds liquidity to the pool.
     * @param poolKey The key of the pool.
     * @param amount0 The amount of token0 to add.
     * @param amount1 The amount of token1 to add.
     * @return liquidity The amount of liquidity added.
     */
    function addLiquidity(
        PoolKey memory poolKey,
        uint256 amount0,
        uint256 amount1
    ) external returns (uint256 liquidity) {
        PoolId poolId = poolKey.toId();

        (uint160 sqrtPriceX96, , , ) = manager.getSlot0(poolId);

        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        uint128 poolLiquidity = manager.getLiquidity(poolId);

        // Only supporting one range of liquidity for now
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(minTick),
            TickMath.getSqrtPriceAtTick(maxTick),
            amount0,
            amount1
        );

        if (poolLiquidity + liquidity < MINIMUM_LIQUIDITY) {
            revert LiquidityDoesntMeetMinimum();
        }

        BalanceDelta addedDelta = modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: minTick,
                tickUpper: maxTick,
                liquidityDelta: liquidity.toInt256(),
                salt: 0
            }),
            ZERO_BYTES,
            false
        );

        if (poolLiquidity == 0) {
            liquidity -= MINIMUM_LIQUIDITY;
            UniswapV4ERC20(vaultLiquidityToken[poolId]).mint(
                address(0),
                MINIMUM_LIQUIDITY
            );
        }

        // mint sender's share of the vault
        UniswapV4ERC20(vaultLiquidityToken[poolId]).mint(msg.sender, liquidity);

        if (
            uint128(-addedDelta.amount0()) < amount0 ||
            uint128(-addedDelta.amount1()) < amount1
        ) {
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
    function removeLiquidity(
        PoolKey memory poolKey,
        uint256 amount0,
        uint256 amount1
    ) external {
        PoolId poolId = poolKey.toId();

        (uint160 sqrtPriceX96, , , ) = manager.getSlot0(poolId);

        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        uint128 liquidityToRemove = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(minTick),
            TickMath.getSqrtPriceAtTick(maxTick),
            amount0,
            amount1
        );

        BalanceDelta delta = modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: minTick,
                tickUpper: maxTick,
                liquidityDelta: -(liquidityToRemove.toInt256()),
                salt: 0
            }),
            ZERO_BYTES,
            true
        );

        UniswapV4ERC20(vaultLiquidityToken[poolId]).burn(
            msg.sender,
            uint256(liquidityToRemove)
        );

        if (
            uint128(-delta.amount0()) < amount0 ||
            uint128(-delta.amount1()) < amount1
        ) {
            revert TooMuchSlippage();
        }

        emit LiquidityRemoved(amount0, amount1);
    }

    /**
     * @notice Automatically rebalances the pool if required. Called in afterSwap.
     * @param poolKey The key of the pool.
     */
    function autoRebalance(PoolKey memory poolKey) public {
        (
            bool _rebalanceRequired,
            LiquidityData memory liquidityData
        ) = rebalanceRequired(poolKey);
        if (_rebalanceRequired) {
            _rebalance(poolKey, liquidityData);
        }
    }

    /**
     * @notice Checks if rebalancing is required for the pool.
     * @param poolKey The key of the pool.
     * @return bool True if rebalancing is required, false otherwise.
     * @return LiquidityData to shift to
     */
    function rebalanceRequired(
        PoolKey memory poolKey
    ) public view returns (bool, LiquidityData memory) {
        PoolId poolId = poolKey.toId();

        LiquidityData memory liquidityData = liquidityOracle.getLiquidityData(
            poolId
        );
        if (
            liquidityData.tickLower != minTick ||
            liquidityData.tickUpper != maxTick
        ) {
            return (true, liquidityData);
        }
        return (false, liquidityData);
    }

    /**
     * @notice Modifies the liquidity of the pool.
     * @param poolKey The key of the pool.
     * @param params The parameters for modifying liquidity.
     * @param hookData Additional data for the hook.
     * @param settleUsingBurn Whether to settle using burn.
     * @return delta The balance delta after modification.
     */
    function modifyLiquidity(
        PoolKey memory poolKey,
        IPoolManager.ModifyLiquidityParams memory params,
        bytes memory hookData,
        bool settleUsingBurn
    ) internal returns (BalanceDelta delta) {
        delta = abi.decode(
            manager.unlock(
                abi.encode(
                    CallbackData(
                        msg.sender,
                        poolKey,
                        params,
                        hookData,
                        settleUsingBurn,
                        false
                    )
                )
            ),
            (BalanceDelta)
        );
    }

    /**
     * @notice Callback function for unlocking the vault, which is called during modifyLiquidity.
     * @param rawData The raw data for the callback.
     * @return bytes The encoded balance delta.
     */
    function _unlockVaultCallback(
        bytes calldata rawData
    ) internal virtual returns (bytes memory) {
        require(
            msg.sender == address(manager),
            "Callback not called by manager"
        );

        CallbackData memory data = abi.decode(rawData, (CallbackData));
        BalanceDelta delta;

        (delta, ) = manager.modifyLiquidity(data.key, data.params, ZERO_BYTES);
        _settleDeltas(
            data.sender,
            data.key,
            delta.amount0(),
            delta.amount1(),
            data.takeClaims,
            data.settleUsingBurn
        );

        return abi.encode(delta);
    }

    /**
     * @notice Settles the deltas for a given sender and pool key.
     * @param sender The address of the sender.
     * @param key The key of the pool.
     * @param delta0 The balance of currency 0 to settle
     * @param delta1 the balance of currency 1 to settle
     */
    function _settleDeltas(
        address sender,
        PoolKey memory key,
        int256 delta0,
        int256 delta1,
        bool takeClaims,
        bool settleUsingBurn
    ) internal {
        if (delta0 < 0) {
            _settle(key.currency0, sender, uint256(-delta0), settleUsingBurn);
        }
        if (delta1 < 0) {
            _settle(key.currency1, sender, uint256(-delta1), settleUsingBurn);
        }
        if (delta0 > 0) {
            _take(key.currency0, sender, uint256(delta0), takeClaims);
        }
        if (delta1 > 0) {
            _take(key.currency1, sender, uint256(delta1), takeClaims);
        }
    }

    /**
     * @notice Settles a given amount of currency, paying the pool.
     * @param currency The currency to settle.
     * @param payer The address of the payer.
     * @param amount The amount to settle.
     * @param burn Whether to burn the amount.
     */
    function _settle(
        Currency currency,
        address payer,
        uint256 amount,
        bool burn
    ) internal {
        if (burn) {
            manager.burn(payer, currency.toId(), amount);
        } else if (currency.isNative()) {
            manager.settle{value: amount}(currency);
        } else {
            manager.sync(currency);
            if (payer != address(this)) {
                IERC20(Currency.unwrap(currency)).transferFrom(
                    payer,
                    address(manager),
                    amount
                );
            } else {
                IERC20(Currency.unwrap(currency)).transfer(
                    address(manager),
                    amount
                );
            }
            manager.settle(currency);
        }
    }

    /**
     * @notice Takes a given amount of currency.
     * @param currency The currency to take.
     * @param recipient The address of the recipient.
     * @param amount The amount to take.
     * @param claims Whether to take claims.
     */
    function _take(
        Currency currency,
        address recipient,
        uint256 amount,
        bool claims
    ) internal {
        if (claims) {
            manager.mint(recipient, currency.toId(), amount);
        } else {
            manager.take(currency, recipient, amount);
        }
    }

    /**
     * @notice Rebalances the pool.
     * @param key The key of the pool.
     */
    function _rebalance(
        PoolKey memory key,
        LiquidityData memory liquidityData
    ) internal {
        PoolId poolId = key.toId();

        Position.Info memory position = manager.getPosition(
            poolId,
            address(this),
            minTick,
            maxTick,
            0
        );

        uint256 oldLiquidity = uint256(position.liquidity);

        // remove liquidity in position
        (BalanceDelta balanceDelta, ) = manager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: minTick,
                tickUpper: maxTick,
                liquidityDelta: -int256(oldLiquidity),
                salt: 0
            }),
            ZERO_BYTES
        );

        // get current price
        (uint160 sqrtPriceX96, , , ) = manager.getSlot0(poolId);

        (
            uint256 newLiquidity,
            int256 amount0Delta,
            int256 amount1Delta
        ) = _getLiquidityAndAmounts(
                oldLiquidity,
                sqrtPriceX96,
                liquidityData,
                balanceDelta
            );

        if (amount0Delta != 0 && amount1Delta != 0) {
            // means amount0 must be sold if true
            bool zeroForOne = amount0Delta < 0;

            manager.swap(
                key,
                IPoolManager.SwapParams({
                    zeroForOne: zeroForOne,
                    amountSpecified: zeroForOne ? amount0Delta : amount1Delta, // how much of the token to sell
                    // allow for slippage
                    sqrtPriceLimitX96: zeroForOne
                        ? TickMath.MIN_SQRT_PRICE + 1
                        : TickMath.MAX_SQRT_PRICE - 1
                }),
                abi.encode(false)
            );

            // set optimal liquidity
            manager.modifyLiquidity(
                key,
                IPoolManager.ModifyLiquidityParams({
                    tickLower: liquidityData.tickLower,
                    tickUpper: liquidityData.tickUpper,
                    liquidityDelta: -int256(newLiquidity), // adding to the pool
                    salt: 0
                }),
                ZERO_BYTES
            );
        }

        int256 delta0 = manager.currencyDelta(address(this), key.currency0);
        int256 delta1 = manager.currencyDelta(address(this), key.currency1);

        _settleDeltas(address(this), key, delta0, delta1, true, false);
        emit RebalanceOccurred(
            poolId,
            minTick,
            maxTick,
            liquidityData.tickLower,
            liquidityData.tickUpper
        );

        minTick = liquidityData.tickLower;
        maxTick = liquidityData.tickUpper;
    }

    function _getLiquidityAndAmounts(
        uint256 oldLiquidity,
        uint160 sqrtPriceX96,
        LiquidityData memory liquidityData,
        BalanceDelta balanceDelta
    )
        internal
        view
        returns (uint256 newLiquidity, int256 amount0Delta, int256 amount1Delta)
    {
        uint256 sqrtPl = TickMath.getSqrtPriceAtTick(minTick);
        uint256 sqrtPu = TickMath.getSqrtPriceAtTick(maxTick);
        uint256 sqrtPlNew = TickMath.getSqrtPriceAtTick(
            liquidityData.tickLower
        );
        uint256 sqrtPuNew = TickMath.getSqrtPriceAtTick(
            liquidityData.tickUpper
        );

        // find new liquidity
        newLiquidity = _calculateNewLiquidity(
            oldLiquidity,
            sqrtPl,
            sqrtPu,
            sqrtPriceX96,
            sqrtPlNew,
            sqrtPuNew
        );

        // calculate how much of token0 and token1 should be added
        (uint256 newAmount0, uint256 newAmount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                sqrtPriceX96,
                sqrtPlNew.toUint160(),
                sqrtPuNew.toUint160(),
                newLiquidity.toUint128()
            );

        // how much token0 to sell
        amount0Delta = int256(newAmount0) - balanceDelta.amount0();
        amount1Delta = int256(newAmount1) - balanceDelta.amount1();
    }

    /**
     * See Unicast math doc
     */
    function _calculateNewLiquidity(
        uint256 L,
        uint256 sqrtPl,
        uint256 sqrtPu,
        uint256 sqrtPc,
        uint256 sqrtPlNew,
        uint256 sqrtPuNew
    ) internal pure returns (uint256) {
        // Calculate normal current price, but keep in X96 format
        // in order to do operations with the others
        uint256 PcX96 = (sqrtPc ** 2) >> FixedPoint96.RESOLUTION;

        // Calculate numerator terms
        uint256 numerator = (sqrtPu - sqrtPl) /
            (sqrtPc * sqrtPu) +
            PcX96 *
            (sqrtPc - sqrtPl);

        // Calculate denominator terms
        uint256 denominator = (sqrtPuNew - sqrtPlNew) /
            (sqrtPc * sqrtPuNew) +
            PcX96 *
            (sqrtPc - sqrtPlNew);

        // Calculate new L
        return
            (L << FixedPoint96.RESOLUTION).mulDiv(numerator, denominator) >>
            FixedPoint96.RESOLUTION;
    }
}
