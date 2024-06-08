// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IVolatilityOracle {
    function getVolatility() external view returns (uint24);
}