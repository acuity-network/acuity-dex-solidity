// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {AtomicSwap} from "../src/AtomicSwap.sol";

contract AtomicSwapTest is Test {
    AtomicSwap public atomicSwap;

    function setUp() public {
        atomicSwap = new AtomicSwap();
    }

    function test_Increment() public {
        // counter.increment();
        // assertEq(counter.number(), 1);
    }

    function testFuzz_SetNumber(uint256 x) public {
        // counter.setNumber(x);
        // assertEq(counter.number(), x);
    }
}
