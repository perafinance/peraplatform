//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./TradeFarming.sol";

/// @author Ulaş Erdoğan
/// @title Trade Farming Factory Contract 
/// @dev Deploys new trade farming contracts and store their addresses by transferring its ownership to msg.sender
contract TradeFarmingFactory is Ownable {
    // The addresses of deployed trade farming contracts
    address[] public createdContracts;


    /**
     * @notice Factory function - takes the parameters of the competition of Token - Avax pairs
     * @param _routerAddress address of the DEX router contract
     * @param _tokenAddress IERC20 - address of the token of the pair
     * @param _rewardAddress IERC20 - address of the reward token
     * @param _previousVolume uint256 - average of previous days
     * @param _previousDay uint256 - previous considered days
     * @param _totalDays uint256 - total days of the competition
     * @param _owner address - the address which will be the owner
     */
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
        // Deploying the contract
        TFcontract = new TradeFarming(
            _routerAddress,
            _tokenAddress,
            _rewardAddress,
            _previousVolume,
            _previousDay,
            _totalDays
        );
        // Transferring the ownership of the contract to the msg.sender
        TFcontract.transferOwnership(_owner);
        // Storing the address of the contract
        createdContracts.push(address(TFcontract));
    }

    /**
    * @notice Easily access the last created contracts address
    * @return address - the address of the last deployed contract
    */
    function getLastContract() external view returns (address) {
        return createdContracts[createdContracts.length - 1];
    }
}
