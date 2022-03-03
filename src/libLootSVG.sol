// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {Base64} from "openzeppelin-contracts/contracts/utils/Base64.sol";

library LootSVG {

    function tokenURIBuilder(uint256 id) public view returns (string memory) {
        string[17] memory parts;
        parts[0] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>.base { fill: black; font-family: serif; font-size: 14px; }</style><rect width="100%" height="100%" fill="white" /><text x="10" y="20" class="base">NFT ID: ';

        parts[1] = Strings.toString(id);

        parts[2] = '</text><text x="10" y="40" class="base"> Collection: 0x';

        parts[3] = toAsciiString(address(this));

        parts[4] = '</text></svg>';

        string memory output = string(abi.encodePacked(parts[0], parts[1], parts[2], parts[3], parts[4]));
        
        string memory json = Base64.encode(bytes(string(abi.encodePacked('{"name": "Mock NFT #', Strings.toString(id), '", "description": "Mock NFT with SVG metadata.", "image": "data:image/svg+xml;base64,', Base64.encode(bytes(output)), '"}'))));
        output = string(abi.encodePacked('data:application/json;base64,', json));

        return output;
    }

    function toAsciiString(address x) internal pure returns (string memory) {
    bytes memory s = new bytes(40);
    for (uint i = 0; i < 20; i++) {
        bytes1 b = bytes1(uint8(uint(uint160(x)) / (2**(8*(19 - i)))));
        bytes1 hi = bytes1(uint8(b) / 16);
        bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
        s[2*i] = char(hi);
        s[2*i+1] = char(lo);            
    }
    return string(s);
}

    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }

}