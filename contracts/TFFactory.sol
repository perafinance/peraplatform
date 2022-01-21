//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./TradeFarming.sol";

contract TradeFarmingFactory is Ownable {
    address[] public createdContracts;

    function createTnAPair(
        address _routerAddress,
        address _tokenAddress,
        address _rewardAddress,
        uint256 _previousVolume,
        uint256 _previousDay,
        uint256 _totalDays,
        address _owner
    ) external onlyOwner {
        TradeFarming TFcontract;
        TFcontract = new TradeFarming(
            _routerAddress,
            _tokenAddress,
            _rewardAddress,
            _previousVolume,
            _previousDay,
            _totalDays
        );
        TFcontract.transferOwnership(msg.sender);
        createdContracts.push(address(TFcontract));
    }

    function getLastContract() external view returns (address) {
        return createdContracts[createdContracts.length - 1];
    }
}
