/*
    Created for test purposes on Avalanche Fuji Testnet 
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts@4.4.0/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts@4.4.0/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts@4.4.0/access/Ownable.sol";

contract USDCoin is ERC20, ERC20Burnable, Ownable {
    constructor() ERC20("USD Coin", "USDC.e") {
        _mint(msg.sender, 1000000000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}