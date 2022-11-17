// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./ERC721Royal.sol";

contract Custom is ERC721Royal, Ownable {
    string[] tokenURIs;
    uint256 public totalMinted;
    // Mapping from token ID to tokenURI
    mapping(uint256 => string) private tokenUris;

    constructor() ERC721("Custom", "Custom") {}

    function mint(
        string memory path,
        uint8 copy,
        uint8 royalty
    ) external {
        uint256 i;
        for (i = 0; i < copy; ++i) {
            _royalMint(msg.sender, ++totalMinted, royalty);
            tokenUris[totalMinted] = path;
        }
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(tokenId), "This token does not exist");
        return tokenUris[tokenId];
    }
}       
