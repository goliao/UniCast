// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {UniCastOracle} from "../src/UniCastOracle.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {UniCastVolitilityFee} from "../src/UniCastVolitilityFee.sol";
import {console} from "forge-std/console.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {UniCastHook} from "../src/UniCastHook.sol";
import {LiquidityData} from "../src/interface/IUniCastOracle.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {StateLibrary} from "../src/util/StateLibrary.sol";

contract TestUniCast is Test, Deployers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    address targetAddr =
        address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG |
                    Hooks.BEFORE_SWAP_FLAG |
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.AFTER_SWAP_FLAG
            )
        );
    UniCastHook hook = UniCastHook(targetAddr);
    address oracleAddr = makeAddr("oracle");
    UniCastOracle oracle = UniCastOracle(oracleAddr);
    MockERC20 token0;
    MockERC20 token1;

    uint128 constant EXPECTED_LIQUIDITY = 250763249753729650363;
    int24 constant INITIAL_MAX_TICK = 120;

    error MustUseDynamicFee();
    event RebalanceOccurred(PoolId poolId);

    PoolSwapTest.TestSettings testSettings =
        PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

    function setUp() public {
        emit log_named_address("targetAddr", targetAddr);
        // Deploy v4-core
        deployFreshManagerAndRouters();

        deployCodeTo(
            "UniCastHook.sol",
            abi.encode(
                manager,
                oracleAddr,
                -INITIAL_MAX_TICK,
                INITIAL_MAX_TICK
            ),
            targetAddr
        );

        // Deploy, mint tokens, and approve all periphery contracts for two tokens
        (currency0, currency1) = deployMintAndApprove2Currencies();
        token0 = MockERC20(Currency.unwrap(currency0));
        token1 = MockERC20(Currency.unwrap(currency1));
        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);

        emit log_address(address(hook));

        // Initialize a pool
        (key, ) = initPool(
            currency0,
            currency1,
            hook,
            LPFeeLibrary.DYNAMIC_FEE_FLAG, // Set the `DYNAMIC_FEE_FLAG` in place of specifying a fixed fee
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );
        emit log_uint(key.fee);

        // issue liquidity and allowance
        address gordon = makeAddr("gordon");
        vm.startPrank(gordon);
        token0.mint(gordon, 10000 ether);
        token1.mint(gordon, 10000 ether);
        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);

        hook.addLiquidity(key, 10 ether, 10 ether);
        vm.stopPrank();

        // mint to vault, which becomes an LP basically 
        token0.mint(address(hook), 1000 ether);
        token1.mint(address(hook), 1000 ether);
    }

    function testEtch() public view {
        assertEq(address(hook), targetAddr);
    }

    function testVolatilityOracleAddress() public view {
        assertEq(oracleAddr, address(hook.getVolatilityOracle()));
    }

    function testGetFeeWithVolatility() public {
        PoolId poolId = key.toId();
        vm.mockCall(
            oracleAddr,
            abi.encodeWithSelector(oracle.getFee.selector, poolId),
            abi.encode(uint24(650))
        );
        uint128 fee = hook.getFee(poolId);
        console.logUint(fee);
        assertEq(fee, 650);
    }

    function testBeforeInitializeRevertsIfNotDynamic() public {
        vm.expectRevert(abi.encodeWithSelector(MustUseDynamicFee.selector));
        initPool(
            currency0,
            currency1,
            hook,
            100, // Set the `DYNAMIC_FEE_FLAG` in place of specifying a fixed fee
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );
    }

    function testBeforeSwapVolatile() public {
        PoolId poolId = key.toId();
        vm.mockCall(
            oracleAddr,
            abi.encodeWithSelector(oracle.getFee.selector),
            abi.encode(uint24(650))
        );
        vm.mockCall(
            oracleAddr,
            abi.encodeWithSelector(oracle.getLiquidityData.selector, poolId),
            abi.encode(LiquidityData(-INITIAL_MAX_TICK, INITIAL_MAX_TICK))
        );
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -0.01 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        // 1. Conduct a swap at baseline vol
        // This should just use `BASE_FEE`
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        assertEq(_fetchPoolLPFee(key), 650);
        (bool accruedFees, ) = hook.poolInfos(poolId);
        assertEq(accruedFees, true);
    }

    function testBeforeSwapNotVolatile() public {
        PoolId poolId = key.toId();
        vm.mockCall(
            oracleAddr,
            abi.encodeWithSelector(oracle.getFee.selector),
            abi.encode(uint24(500))
        );
        vm.mockCall(
            oracleAddr,
            abi.encodeWithSelector(oracle.getLiquidityData.selector, poolId),
            abi.encode(LiquidityData(-INITIAL_MAX_TICK, INITIAL_MAX_TICK))
        );
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -0.01 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        // 1. Conduct a swap at baseline vol
        // This should just use `BASE_FEE`
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        assertEq(_fetchPoolLPFee(key), 500);
    }

    function _fetchPoolLPFee(
        PoolKey memory _key
    ) internal view returns (uint256 lpFee) {
        PoolId id = _key.toId();
        (, , , lpFee) = manager.getSlot0(id);
    }

    function testAddLiquidity() public {
        address alice = makeAddr("alice");
        vm.startPrank(alice);
        token0.mint(alice, 1000 ether);
        token1.mint(alice, 1000 ether);
        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);

        uint256 liquidity = hook.addLiquidity(key, 1.5 ether, 1.5 ether);
        assertEq(
            liquidity,
            EXPECTED_LIQUIDITY,
            "Liquidity should be exactly 250763249753729650363 according to equation"
        );

        vm.stopPrank();
    }

    function testAddLiquidityNegative() public {
        address alice = makeAddr("alice");
        vm.startPrank(alice);
        token0.mint(alice, 0.5 ether); // Insufficient amount
        token1.mint(alice, 0.5 ether); // Insufficient amount
        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);

        vm.expectRevert();
        hook.addLiquidity(key, 1.5 ether, 1.5 ether);

        vm.stopPrank();
    }

    function testRemoveLiquidity() public {
        address bob = makeAddr("bob");
        vm.startPrank(bob);
        token0.mint(bob, 1000 ether);
        token1.mint(bob, 1000 ether);
        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);

        uint256 liquidity = hook.addLiquidity(key, 1.5 ether, 1.5 ether);
        assertEq(
            liquidity,
            EXPECTED_LIQUIDITY,
            "Liquidity should be exactly 250763249753729650363"
        );

        hook.removeLiquidity(key, 0.5 ether, 1 ether);

        uint256 balance0 = token0.balanceOf(bob);
        uint256 balance1 = token1.balanceOf(bob);
        assertApproxEqAbs(
            balance0,
            998.5 ether,
            0.5 ether,
            "Token0 balance should be approximately 998.5 ether after removing liquidity"
        );
        assertApproxEqAbs(
            balance1,
            999 ether,
            0.5 ether,
            "Token1 balance should be approximately 999 ether after removing liquidity"
        );
        vm.stopPrank();
    }

    function testRemoveLiquidityNegative() public {
        address bob = makeAddr("bob");
        vm.startPrank(bob);
        token0.mint(bob, 1000 ether);
        token1.mint(bob, 1000 ether);
        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);

        uint256 liquidity = hook.addLiquidity(key, 1.5 ether, 1.5 ether);
        assertEq(
            liquidity,
            EXPECTED_LIQUIDITY,
            "Liquidity should be exactly 250763249753729650363"
        );

        vm.expectRevert();
        hook.removeLiquidity(key, 2 ether, 2 ether);
        vm.stopPrank();
    }

    function testRebalanceAfterSwap() public {
        PoolId poolId = key.toId();
        vm.expectEmit(targetAddr);
        emit RebalanceOccurred(poolId);
        vm.mockCall(
            oracleAddr,
            abi.encodeWithSelector(oracle.getFee.selector, poolId),
            abi.encode(uint24(500))
        );
        vm.expectCall(
            oracleAddr,
            abi.encodeCall(oracle.getLiquidityData, (poolId))
        );
        vm.mockCall(
            oracleAddr,
            abi.encodeWithSelector(oracle.getLiquidityData.selector, poolId),
            abi.encode(LiquidityData(-INITIAL_MAX_TICK, 2 * INITIAL_MAX_TICK))
        );
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        swapRouter.swap(key, params, testSettings, abi.encode(true)); // hookdata is firstSwap

        // Check if rebalancing occurred
        (bool accruedFees, ) = hook.poolInfos(poolId);
        assertTrue(
            accruedFees,
            "Rebalancing should have occurred and set hasAccruedFees to true"
        );
        vm.stopPrank();
    }

    function testRebalanceAfterSwapNegative() public {
        PoolId poolId = key.toId();
        // Check if rebalancing did not occur with no swaps
        (bool accruedFees, ) = hook.poolInfos(poolId);
        assertFalse(
            accruedFees,
            "Rebalancing should not have occurred and hasAccruedFees should be false"
        );

        vm.stopPrank();
    }
}
