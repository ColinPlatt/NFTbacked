// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "solmate/tokens/ERC721.sol";
import {LootSVG} from "./libLootSVG.sol";

contract mockERC721 is ERC721 {
    using LootSVG for uint256;

    constructor(
        string memory _name, 
        string memory _symbol
    )
        ERC721(_name, _symbol){}

    
    function tokenURI(uint256 id) public view override returns (string memory) {
        return id.tokenURIBuilder();
    }

    function mint(uint256 id) public {
        _mint(msg.sender, id);
    }

    function mint(address to, uint256 id) public {
        _mint(to, id);
    }

}