// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

abstract contract ERC721Royal is ERC721Enumerable {
    mapping(uint256 => address) private creators;
    mapping(uint256 => uint8) private royalty;
    mapping(address => uint256[]) private creations;

    function _royalMint(
        address addr,
        uint256 index,
        uint8 rlt
    ) internal {
        require(rlt >= 0, "Royalty should be more than 0");
        require(rlt <= 10, "Royalty should be less than 10");
        creators[index] = addr;
        royalty[index] = rlt;
        creations[addr].push(index);
        _safeMint(addr, index);
    }

    function getRoyalty(uint256 tokenId) external view returns (uint8) {
        return royalty[tokenId];
    }

    function getCreator(uint256 tokenId) external view returns (address) {
        return creators[tokenId];
    }

    function getNFTByCreator(address addr)
        external
        view
        returns (uint256[] memory)
    {
        return creations[addr];
    }
}
