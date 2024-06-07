pragma solidity ^0.8.0;

import "forge-std/console.sol"; // Import the console library
import "forge-std/Test.sol";

contract MyContract {
    event MyEvent(uint256 value);

    function emitEvent() public {
        if (block.number == 12355) {
            console.log("Emitting MyEvent with value 1 at block", block.number); // Log message
            emit MyEvent(1);
        } else {
            console.log("Emitting MyEvent with value 0 at block", block.number); // Log message
            emit MyEvent(0);
        }
    }
}

contract MyContractTest is Test {
    MyContract public myContract;

    function setUp() public {
        myContract = new MyContract();
    }

    function testMyEvent() public {
        // Set the starting block number to T (e.g., 12345)
        uint256 T = 12345;
        vm.roll(T);
        console.log("Setting starting block number to", T);

        // Emit the event with value 0 for blocks T to T+9
        for (uint256 i = 0; i < 10; i++) {
            vm.expectEmit(true, true, true, true);
            emit MyContract.MyEvent(0);
            console.log("Rolling to block", block.number, "Expecting MyEvent with value 0");
            myContract.emitEvent();
            vm.roll(block.number + 1);
        }



        // Emit the event with value 1 at block 12355
        uint256 targetBlock = 12355;
        vm.roll(targetBlock);
        console.log("Rolling to block", targetBlock, "Expecting MyEvent with value 1");

        vm.expectEmit(true, true, true, true);
        emit MyContract.MyEvent(1);
        myContract.emitEvent();
    }
}