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
import {IUniCastOracle} from "../src/interface/IUniCastOracle.sol";
import {LiquidityData} from "../src/interface/IUniCastOracle.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {StateLibrary} from "../src/util/StateLibrary.sol";

contract TestUniCast is Test, Deployers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager; 

    address targetAddr = address(uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.AFTER_SWAP_FLAG
        ));
    address keeper = makeAddr("keeper");
    UniCastHook hook = UniCastHook(targetAddr);
    IUniCastOracle oracle;
    MockERC20 token0;
    MockERC20 token1;

    error MustUseDynamicFee();

    PoolSwapTest.TestSettings testSettings = PoolSwapTest
        .TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

    function setUp() public {
        emit log_named_address("targetAddr", targetAddr);
        // Deploy v4-core
        deployFreshManagerAndRouters();

        oracle = new UniCastOracle(keeper, 500);

        deployCodeTo(
            "UniCastHook.sol", 
            abi.encode(manager, address(oracle)),
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
    }

    function testVolatilityOracleAddress() public view {
        assertEq(address(oracle), address(hook.getVolatilityOracle()));
    }
    function testGetFeeWithNoVolatility() public view {
        uint128 fee = hook.getFee(key.toId());
        assertEq(fee, 500);
    }

    function testSetImpliedVolatility() public {
        PoolId poolId = key.toId();

        vm.startPrank(keeper);
        oracle.setFee(poolId, 650);
        uint128 fee = hook.getFee(poolId);
        assertEq(fee, 650);
    }

    function testBeforeSwapNotVolatile() public {
        PoolId poolId = key.toId();
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -0.01 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        // 1. Conduct a swap at baseline vol
        // This should just use `BASE_FEE` 
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        assertEq(_fetchPoolLPFee(key), 500);
        (bool accruedFees,) = hook.poolInfos(poolId);
        assertEq(accruedFees, true);
    }

    function testRebalanceAfterSwap() public {
        PoolId poolId = key.toId();
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        // Check if rebalancing occurred
        (bool accruedFees,) = hook.poolInfos(poolId);
        assertTrue(accruedFees, "Rebalancing should have occurred and set hasAccruedFees to true");

        vm.stopPrank();
    }

    function _fetchPoolLPFee(PoolKey memory _key) internal view returns (uint256 lpFee) {
        PoolId id = _key.toId();
        (,,, lpFee) = manager.getSlot0(id);
    }

}
