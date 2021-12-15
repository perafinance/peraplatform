//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./TradeFarming.sol";

contract TradeFarmingFactory is Ownable {
    function createTnAPair(
        address _routerAddress,
        address _tokenAddress,
        address _rewardAddress,
        uint256 _previousVolume,
        uint256 _previousDay,
        uint256 _totalDays
    ) public onlyOwner returns (address) {
        TradeFarming TFcontract;
        TFcontract = new TradeFarming(
            _routerAddress,
            _tokenAddress,
            _rewardAddress,
            _previousVolume,
            _previousDay,
            _totalDays
        );

        return address(TFcontract);
    }
}
