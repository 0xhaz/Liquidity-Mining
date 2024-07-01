// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

library TransientMapping {
    function tload(mapping(PoolId => BalanceDelta simulatedSwapDelta) storage self, PoolId poolId)
        internal
        view
        returns (BalanceDelta result)
    {
        assembly {
            mstore(0, poolId)
            mstore(0x20, self.slot)
            result := tload(keccak256(0, 0x40))
        }
    }

    function tstore(mapping(PoolId => BalanceDelta simulatedSwapDelta) storage self, PoolId poolId, BalanceDelta value)
        internal
    {
        assembly {
            mstore(0, poolId)
            mstore(0x20, self.slot)
            tstore(keccak256(0, 0x40), value)
        }
    }
}
