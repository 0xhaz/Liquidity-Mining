// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookHelpers} from "./utils/HookHelpers.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {NoOpHook, hookPermissions} from "../src/NoOpHook.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {FixedPoint128} from "@uniswap/v4-core/src/libraries/FixedPoint128.sol";
import {ERC20} from "solmate/utils/SafeTransferLib.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";

contract StreamToken is ERC20("StreamToken", "REWARD", 18) {
    function mint(uint256 amount) public virtual {
        _mint(msg.sender, amount);
    }
}

contract NoOpHookTest is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using HookHelpers for Hooks.Permissions;
    using StateLibrary for IPoolManager;

    uint256 constant Q32 = 1 << 32;

    NoOpHook hook;
    PoolId poolId;
    StreamToken streamToken;

    struct PositionRef {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        bytes32 salt;
    }

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        Deployers.deployFreshManagerAndRouters();
        Deployers.deployMintAndApprove2Currencies();

        // Deploy the hook to an address with the correct flags
        uint160 flags = hookPermissions().flags();
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(NoOpHook).creationCode, abi.encode(address(manager)));
        hook = new NoOpHook{salt: salt}(IPoolManager(address(manager)));
        require(address(hook) == hookAddress, "hook address mismatch");

        // Create a pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(address(hook)));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);
    }

    function addLiquidity(int24 tickLower, int24 tickUpper) internal returns (PositionRef memory) {
        return addLiquidity(1e18, tickLower, tickUpper, bytes32(0));
    }

    function addLiquidity(int256 liquidityDelta, int24 tickLower, int24 tickUpper, bytes32 salt)
        internal
        returns (PositionRef memory)
    {
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidityDelta,
                salt: salt
            }),
            ZERO_BYTES
        );
        return PositionRef(address(modifyLiquidityRouter), tickLower, tickUpper, salt);
    }

    function swap2(PoolKey memory _key, bool zeroForOne, int256 amountSpecified, bytes memory hookData)
        internal
        returns (BalanceDelta value)
    {
        value = swap(_key, zeroForOne, amountSpecified, hookData);
    }

    function testBenchmarks() public {
        // Add liquidity
        addLiquidity({tickLower: -1200, tickUpper: 1200});
        addLiquidity({tickLower: -1200, tickUpper: 3000});
        addLiquidity({tickLower: -3000, tickUpper: -1500});

        swap2(key, false, 0.09 ether, ZERO_BYTES);
    }
}
