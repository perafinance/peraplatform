// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BUIDL is ERC20, ERC20Burnable, Ownable {
    constructor() ERC20("Buidl Token", "BUIDL") {
        _mint(msg.sender, 300_000 * 10 ** decimals());
        _mint(msg.sender, 5_000 * 10 ** decimals());

    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}