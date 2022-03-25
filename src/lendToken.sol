// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "solmate/tokens/erc20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract lendToken is ERC20, Ownable {

    constructor() ERC20("lendToken", "lToken", 18){}

    function mint(uint256 amt) public onlyOwner {
        _mint(msg.sender, amt);
    }

    function mint(address to, uint256 amt) public onlyOwner {
        _mint(to, amt);
    }

    function burn(address from, uint256 amt) public onlyOwner {
        _burn(from, amt);
    }

}