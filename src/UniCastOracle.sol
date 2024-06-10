pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {IUniCastOracle, LiquidityData} from "./interface/IUniCastOracle.sol";

contract UniCastOracle is Ownable, IUniCastOracle {
    uint24 public impliedVol;
    address public keeper;
    
    event KeeperUpdated(address indexed newKeeper);
    event VolEvent(uint256 value);

    error Unauthorized();

    mapping (PoolId => LiquidityData) public liquidityData;

    modifier onlyKeeper() {
        if (msg.sender != keeper) revert Unauthorized();
        _;
    }

    constructor(address _keeper) Ownable(_keeper) {
        keeper = _keeper;
        impliedVol = 100;
    }

    function setLiquidityData(PoolId _poolId, int24 _tickLower, int24 _tickUpper, int256 _liquidityDelta) external onlyKeeper {
        liquidityData[_poolId] = LiquidityData({
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            liquidityDelta: _liquidityDelta
        });
    }

    function getLiquidityData(PoolId _poolId) external view returns (LiquidityData memory) {
        return liquidityData[_poolId];
    }

    function setImpliedVol(uint24 _impliedVol) external onlyKeeper {
        impliedVol = _impliedVol;
        emit VolEvent(impliedVol);
    }

    function updateKeeper(address _newKeeper) external onlyKeeper {
        keeper = _newKeeper;
        emit KeeperUpdated(_newKeeper);
    }

    function getVolatility() external view override returns (uint24) {
        return impliedVol;
    }
}
