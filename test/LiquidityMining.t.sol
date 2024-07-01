// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

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
import {LiquidityMiningHook, hookPermissions} from "src/LiquidityMiningHook.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {FixedPoint128} from "@uniswap/v4-core/src/libraries/FixedPoint128.sol";
import {ERC20} from "solmate/utils/SafeTransferLib.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";

contract LiquidityMiningTest is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using HookHelpers for Hooks.Permissions;
    using StateLibrary for IPoolManager;

    uint256 constant Q32 = 1 << 32;

    LiquidityMiningHook hook;
    PoolId poolId;
    StreamToken streamToken;

    struct PositionRef {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        bytes32 salt;
    }

    function setUp() public {
        // creates the pool manager, utility routers and test tokens
        Deployers.deployFreshManagerAndRouters();
        Deployers.deployMintAndApprove2Currencies();

        // Deploy the hook to an address with the correct flags
        uint160 flags = hookPermissions().flags();
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(LiquidityMiningHook).creationCode, abi.encode(address(manager)));
        hook = new LiquidityMiningHook{salt: salt}(IPoolManager(address(manager)));
        require(address(hook) == hookAddress, "LiquidityMiningTest: hook address mismatch");

        // create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(address(hook)));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

        streamToken = new StreamToken();
    }

    function testSecondsInside() public {
        //  Liquidity Distribution
        //
        //                                     price
        //  -3000  ----- -1500  --- -1200 -----  0  -----  1200  -----  3000
        //                             ======================
        //                                                   ==============
        //    ===============
        //                     < gap >
        //
        addLiquidity({tickLower: -1200, tickUpper: 1200});
        addLiquidity({tickLower: 1200, tickUpper: 3000});
        addLiquidity({tickLower: -3000, tickUpper: -1500});

        assertEq(hook.getSecondsInside(poolId, -1200, 1200), 0, "check11");
        assertEq(hook.getSecondsInside(poolId, 1200, 3000), 0, "check12");
        assertEq(hook.getSecondsInside(poolId, -3000, -1500), 0, "check13");
        assertEq(hook.getSecondsInside(poolId, -1500, -1200), 0, "check14");
        assertEq(hook.getSecondsInside(poolId, -1500, -3000), 0, "check15");
        assertEq(hook.getSecondsInside(poolId, -3000, -3000), 0, "check16");

        advanceTime(100 seconds);

        assertEq(hook.getSecondsInside(poolId, -1200, 1200), 100 seconds, "check21");
        assertEq(hook.getSecondsInside(poolId, 1200, 3000), 0, "check22");
        assertEq(hook.getSecondsInside(poolId, -3000, -1500), 0, "check23");
        assertEq(hook.getSecondsInside(poolId, -1500, -1200), 0, "check24");
        assertEq(hook.getSecondsInside(poolId, -1500, 3000), 100 seconds, "check25");
        assertEq(hook.getSecondsInside(poolId, -3000, 3000), 100 seconds, "check26");

        swap2(key, false, 0.09 ether, ZERO_BYTES);
        assertEq(currentTick(), 1886); // <====== current tick is updated by swap

        assertEq(hook.getSecondsPerLiquidityInsideX128(poolId, -1200, 1200), perLiquidity(100 seconds), "check31");
        assertEq(hook.getSecondsPerLiquidityInsideX128(poolId, 1200, 3000), 0, "check32");
        assertEq(hook.getSecondsPerLiquidityInsideX128(poolId, -3000, -1500), 0, "check33");
        assertEq(hook.getSecondsPerLiquidityInsideX128(poolId, -1500, -1200), 0, "check34");
        assertEq(hook.getSecondsPerLiquidityInsideX128(poolId, -1500, 3000), perLiquidity(100 seconds), "check35");
        assertEq(hook.getSecondsPerLiquidityInsideX128(poolId, -3000, 3000), perLiquidity(100 seconds), "check36");
    }

    function addLiquidity(int24 tickLower, int24 tickUpper) internal returns (PositionRef memory) {
        return addLiquidity(1e18, tickLower, tickUpper, bytes32(0));
    }

    function addLiquidity(int256 liquidityDelta, int24 tickLower, int24 tickUpper, bytes32 salt)
        internal
        returns (PositionRef memory)
    {
        // add liquidity
        snapStart("modifyLiquidity");
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
        snapEnd();

        return PositionRef(address(modifyLiquidityRouter), tickLower, tickUpper, salt);
    }

    function advanceTime(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
    }

    function currentTick() internal view returns (int24 tickCurrent) {
        PoolId id = key.toId();
        (, tickCurrent,,) = manager.getSlot0(id);
    }

    function logTick() internal view {
        console.logInt(int256(currentTick()));
    }

    function perLiquidity(uint256 secs) internal pure returns (uint160) {
        return uint160(FixedPoint128.Q128 * secs / 1e18);
    }

    function swap2(PoolKey memory _key, bool zeroForOne, int256 amountSpecified, bytes memory hookData)
        internal
        returns (BalanceDelta value)
    {
        snapStart("swap");
        value = swap(_key, zeroForOne, amountSpecified, hookData);
        snapEnd();
    }
}

contract StreamToken is ERC20("StreamToken", "REWARD", 18) {
    function mint(uint256 amount) public virtual {
        _mint(msg.sender, amount);
    }
}
