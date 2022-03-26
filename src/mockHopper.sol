// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "solmate/tokens/ERC721.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

contract mockHopper is ERC721 {

    constructor() ERC721("mock Hoppers", "mHOP"){}

    
    function tokenURI(uint256 id) public pure override returns (string memory) {
        string memory baseUri = "https://hoppersgame.io/api/uri/hopper/";
        return string(abi.encodePacked(baseUri, Strings.toString(id)));
    }

    function mint(uint256 id) public {
        _mint(msg.sender, id);
    }

    function mint(address to, uint256 id) public {
        _mint(to, id);
    }

}