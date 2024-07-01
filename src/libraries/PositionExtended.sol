// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

import {LiquidityPoints} from "./LiquidityPoints.sol";
import {PoolExtended} from "./PoolExtended.sol";
import {TickExtended} from "./TickExtended.sol";

library PositionExtended {
    using StateLibrary for IPoolManager;
    using PoolExtended for *;
    using TickExtended for *;

    struct Info {
        // liquidity points awarded for this position, updated on each positon modification
        uint80 relativeSecondsCumulativeX32;
        // snapshot of getSecondsPerLiquidityInsideX128 for which liquidity points are already awarded
        uint176 secondsPerLiquidityInsideLastX128;
        mapping(ERC20 streamToken => mapping(uint256 rate => uint256)) claimed;
    }

    function update(
        mapping(bytes32 positionKey => PositionExtended.Info) storage self,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt,
        uint128 liquidityLast,
        uint176 secondsPerLiquidityInsideX128
    ) internal returns (PositionExtended.Info storage position) {
        position = get(self, owner, tickLower, tickUpper, salt);

        position.relativeSecondsCumulativeX32 += LiquidityPoints.computeSecondsX32(
            liquidityLast, secondsPerLiquidityInsideX128, position.secondsPerLiquidityInsideLastX128
        );
        position.secondsPerLiquidityInsideLastX128 = secondsPerLiquidityInsideX128;
    }

    /// @notice Gets the position for the owner
    /// @param self The storage mapping
    /// @param owner The owner of the position
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param salt The salt of the position
    /// @return position The position storage pointer
    function get(
        mapping(bytes32 positionKey => PositionExtended.Info) storage self,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt
    ) private view returns (PositionExtended.Info storage position) {
        bytes32 positionKey;

        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x26, salt) // [0x26, 0x46]
            mstore(0x06, tickUpper) // [0x23, 0x26]
            mstore(0x03, tickLower) // [0x20, 0x23]
            mstore(0, owner) // [0x0c, 0x20]
            positionKey := keccak256(0x0c, 0x3a) // len is 58 bytes
            mstore(0x26, 0) // rewrite 0x26 to 0
        }
        position = self[positionKey];
    }
}
