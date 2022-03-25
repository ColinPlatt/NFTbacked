// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "solmate/tokens/erc20.sol";

contract mockUSDC is ERC20 {

    constructor() ERC20("mockUSDC", "mUSDC", 18){}

    function mint(uint256 amt) public {
        _mint(msg.sender, amt);
    }

    function mint(address to, uint256 amt) public {
        _mint(to, amt);
    }

}