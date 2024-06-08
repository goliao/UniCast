// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Initializable {
    bool public initialized;

    modifier initializer {
        require(!initialized, "Already initialized");
        _; 
        initialized = true;
    }
}