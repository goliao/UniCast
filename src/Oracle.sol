pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

contract Oracle is Ownable {
    uint128 public impliedVol;
    address public keeper;
    uint24 public constant BASE_FEE = 500; // 0.05%
    
    event KeeperUpdated(address indexed newKeeper);
    event VolEvent(uint256 value);

    error Unauthorized();

    struct LiquidityData {
        int24 tickLower;
        int24 tickUpper;
        int256 liquidityDelta;   
    }

    mapping (PoolId => LiquidityData) public liquidityData;

    modifier onlyKeeper() {
        if (msg.sender != keeper) revert Unauthorized();
        _;
    }

    constructor(address _keeper) Ownable(_keeper) {
        keeper = _keeper;
    }

    function setLiquidityData(PoolId _poolId, int24 _tickLower, int24 _tickUpper, int256 _liquidityDelta) external onlyKeeper {
        liquidityData[_poolId] = LiquidityData({
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            liquidityDelta: _liquidityDelta
        });
    }

    function setImpliedVol(uint128 _impliedVol) external onlyKeeper {
        impliedVol = _impliedVol;
        emit VolEvent(impliedVol);
    }

    function updateKeeper(address _newKeeper) external onlyKeeper {
        keeper = _newKeeper;
        emit KeeperUpdated(_newKeeper);
    }

    function getFee() public view returns (uint24) {
        if (impliedVol > 20) {
            return uint24(BASE_FEE * impliedVol / 20);
        }
        return BASE_FEE;
    }
}