pragma solidity ^0.8.0;

contract Timestamp {
    function getTimestamp() public view returns(uint) {
        return block.timestamp;
    }

    function getMax() public view returns(uint256) {
        return 2**256 - 1;
    }
}