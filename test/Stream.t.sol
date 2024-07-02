// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Stream} from "src/libraries/Stream.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract StreamTest is Test {
    function testStreamKey(address streamCreator, int24 tickLower, int24 tickUpper, ERC20 rewardToken, uint256 rate)
        public
        pure
    {
        bytes32 hashed = keccak256(
            abi.encodePacked(
                uint48(0), tickLower, tickUpper, streamCreator, uint256(uint160(address(rewardToken))), rate
            )
        );
        assertEq(Stream.key(streamCreator, tickLower, tickUpper, rewardToken, rate), hashed);
    }
}
