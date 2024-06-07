pragma solidity ^0.8.0;

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