// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

library TickExtended {
    using TickExtended for *;
    using StateLibrary for IPoolManager;

    struct Info {
        // the timestamp when the tick was last outside the tick range
        uint48 secondsOutside;
        // the cumulative seconds per liquidity outside the tick range
        uint176 secondsPerLiquidityOutsideX128;
    }

    function cross(
        mapping(int24 tick => TickExtended.Info) storage self,
        int24 tick,
        uint176 secondsPerLiquidityGlobalX128
    ) internal {
        Info storage info = self[tick];
        info.secondsOutside = uint48(block.timestamp - info.secondsOutside);
        info.secondsPerLiquidityOutsideX128 = secondsPerLiquidityGlobalX128 - info.secondsPerLiquidityOutsideX128;
    }

    function update(
        mapping(int24 tick => TickExtended.Info) storage self,
        int24 tickIdx,
        int24 tickCurrent,
        uint176 secondsPerLiquidityGlobalX128,
        PoolId poolId,
        IPoolManager poolManager
    ) internal {
        (uint128 liquidityGrossBefore,) = poolManager.getTickLiquidity(poolId, tickIdx);
        if (liquidityGrossBefore == 0) {
            TickExtended.Info storage tick = self[tickIdx];
            if (tickIdx <= tickCurrent) {
                tick.secondsPerLiquidityOutsideX128 = secondsPerLiquidityGlobalX128;
                tick.secondsOutside = uint48(block.timestamp);
            }
        }
    }
}
