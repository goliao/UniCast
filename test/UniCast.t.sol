// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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
import {HookMiner} from "./utils/HookMiner.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {UniCastVolitilityFee} from "../src/UniCastVolitilityFee.sol";
import {console} from "forge-std/console.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {UniCastHook} from "../src/UniCastHook.sol";
import {UniCastImplementation} from "./shared/UniCastImplementation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import "forge-std/console.sol";

contract TestUniCast is Test, Deployers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    address targetAddr = address(uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.AFTER_SWAP_FLAG
        ));
    UniCastHook hook = UniCastHook(targetAddr);
    address oracleAddr = makeAddr("oracle");
    UniCastOracle oracle = UniCastOracle(oracleAddr);
    MockERC20 token0;
    MockERC20 token1;

    PoolSwapTest.TestSettings testSettings = PoolSwapTest
        .TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

    function setUp() public {
        emit log_named_address("targetAddr", targetAddr);
        // Deploy v4-core
        deployFreshManagerAndRouters();

        deployCodeTo(
            "UniCastHook.sol", 
            abi.encode(manager, oracleAddr),
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

        address gordon = makeAddr("gordon");
        vm.startPrank(gordon);
        token0.mint(gordon, 10000 ether);
        token1.mint(gordon, 10000 ether);
        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);

        hook.addLiquidity(key, 10 ether, 10 ether);
        vm.stopPrank();
    }

    function testEtch() public {
        assertEq(address(hook), targetAddr);
    }

    function testVolatilityOracleAddress() public {
        assertEq(oracleAddr, address(hook.getVolatilityOracle()));
    }
    function testGetFeeWithVolatility() public {
        vm.mockCall(oracleAddr, abi.encodeWithSelector(oracle.getVolatility.selector), abi.encode(uint24(150)));
        uint128 fee = hook.getFee();
        console.logUint(fee);
        assertEq(fee, 500 * 1.5);
    }

    function testSwap() public {
        // IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
        //     zeroForOne: true,
        //     amountSpecified: -0.01 ether,
        //     sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        // });
        // // 1. Conduct a swap at baseline vol
        // // This should just use `BASE_FEE` 
        // uint256 balanceOfToken1Before = currency1.balanceOfSelf();
        // swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        // uint256 balanceOfToken1After = currency1.balanceOfSelf();
        // uint256 outputFromBaseFeeSwap = balanceOfToken1After -
        //     balanceOfToken1Before;
        
        // console.log("outputFromBaseFeeSwap:", outputFromBaseFeeSwap);
        // console.log("balanceOfToken1After:", balanceOfToken1After);

        // assertGt(balanceOfToken1After, balanceOfToken1Before);
    }
}
