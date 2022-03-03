// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";

import {mockERC721} from "../mockERC721.sol";

contract ERC721Test is DSTest {
    
    mockERC721 nft;
    
    function setUp() public {
        nft = new mockERC721("test NFT", "TEST");
    }

    function testMetaData() public {
        assertEq(nft.name(), "test NFT");
        assertEq(nft.symbol(), "TEST");
        nft.mint(0);
        emit log(nft.tokenURI(0));
    }
}
