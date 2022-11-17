// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ClockAuctionBase.sol";
import "./ERC721Royal.sol";

/// @title Clock auction for non-fungible tokens.
/// @notice We omit a fallback function to prevent accidental sends to this contract.
contract ClockAuction is Pausable, ClockAuctionBase, Ownable {
    /// @dev The ERC-165 interface signature for ERC-721.
    ///  Ref: https://github.com/ethereum/EIPs/issues/165
    ///  Ref: https://github.com/ethereum/EIPs/issues/721
    // bytes4 constant InterfaceSignature_ERC721 = bytes4(0x9a20483d);

    /// @dev Remove all Ether from the contract, which is the owner's cuts
    ///  as well as any Ether sent directly to the contract address.
    ///  Always transfers to the NFT contract, but can be called either by
    ///  the owner or the NFT contract.

    /// @dev Creates and begins a new auction.
    /// @param contractAddr - Address of current Smart Contract
    /// @param _tokenId - ID of token to auction, sender must be owner.
    /// @param _startingPrice - Price of item (in wei) at beginning of auction.
    /// @param _endingPrice - Price of item (in wei) at end of auction.
    /// @param _duration - Length of time to move between starting
    ///  price and ending price (in seconds).

    function createAuction(
        address contractAddr,
        uint256 _tokenId,
        uint256 _startingPrice,
        uint256 _endingPrice,
        uint256 _duration
    ) external virtual whenNotPaused {
        // Sanity check that no inputs overflow how many bits we've allocated
        // to store them in the auction struct.
        require(_startingPrice == uint256(uint128(_startingPrice)));
        require(_endingPrice == uint256(uint128(_endingPrice)));
        require(_duration == uint256(uint64(_duration)));

        require(
            _owns(contractAddr, msg.sender, _tokenId),
            "createAuction caller is not owner"
        );

        Auction storage existingAuction = tokenIdToAuctions[contractAddr][
            _tokenId
        ];
        require(
            !_isOnAuction(existingAuction),
            "This token is already in auction"
        );
        _escrow(contractAddr, msg.sender, _tokenId);
        Auction memory auction = Auction(
            // nonFungibleContracts[contractAddr],
            msg.sender,
            uint128(_startingPrice),
            uint128(_endingPrice),
            uint64(_duration),
            uint64(block.timestamp)
        );
        _addAuction(contractAddr, _tokenId, auction);
    }

    /// @dev Bids on an open auction, completing the auction and transferring
    ///  ownership of the NFT if enough Ether is supplied.
    /// @param contractAddr - Address of current Smart Contract
    /// @param tokenId - ID of token to bid on.
    function bid(address contractAddr, uint256 tokenId)
        external
        payable
        virtual
    {
        require(
            !(_owns(contractAddr, msg.sender, tokenId)),
            "bid caller is owner"
        );
        Auction storage auction = tokenIdToAuctions[contractAddr][tokenId];
        require(_isOnAuction(auction), "This token is not in auction");
        // _bid will throw if the bid or funds transfer fails
        _bid(contractAddr, tokenId, msg.value);
        ERC721 nftContract = ERC721(contractAddr);
        nftContract.transferFrom(address(this), msg.sender, tokenId);
    }

    function bidRoyalty(address contractAddr, uint256 tokenId)
        external
        payable
        virtual
    {
        require(
            !(_owns(contractAddr, msg.sender, tokenId)),
            "bid caller is owner"
        );
        Auction storage auction = tokenIdToAuctions[contractAddr][tokenId];
        require(_isOnAuction(auction), "This token is not in auction");
        // _bid will throw if the bid or funds transfer fails
        ERC721Royal nftContract = ERC721Royal(contractAddr);
        _bidRoyalty(
            contractAddr,
            nftContract.getCreator(tokenId),
            tokenId,
            msg.value
        );
        nftContract.transferFrom(address(this), msg.sender, tokenId);
    }

    /// @dev Cancels an auction that hasn't been won yet.
    ///  Returns the NFT to original owner.
    /// @notice This is a state-modifying function that can
    ///  be called while the contract is paused.
    /// @param contractAddr - Address of current Smart Contract
    /// @param _tokenId - ID of token on auction
    function cancelAuction(address contractAddr, uint256 _tokenId) external {
        Auction storage auction = tokenIdToAuctions[contractAddr][_tokenId];
        require(_isOnAuction(auction), "This token is not in auction");
        address seller = auction.seller;
        require(msg.sender == seller, "cancelAuction caller is not owner");
        _cancelAuction(contractAddr, _tokenId);
    }

    /// @dev Cancels an auction when the contract is paused.
    ///  Only the owner may do this, and NFTs are returned to
    ///  the seller. This should only be used in emergencies.
    /// @param contractAddr - Address of current Smart Contract
    /// @param _tokenId - ID of the NFT on auction to cancel.
    function cancelAuctionWhenPaused(address contractAddr, uint256 _tokenId)
        external
        whenPaused
        onlyOwner
    {
        Auction storage auction = tokenIdToAuctions[contractAddr][_tokenId];
        require(_isOnAuction(auction), "This token is not in auction");
        _cancelAuction(contractAddr, _tokenId);
    }

    /// @dev Returns auction info for an NFT on auction.
    /// @param contractAddr - Address of current Smart Contract
    /// @param _tokenId - ID of NFT on auction.
    function getAuction(address contractAddr, uint256 _tokenId)
        external
        view
        returns (
            address seller,
            uint256 startingPrice,
            uint256 endingPrice,
            uint256 duration,
            uint256 startedAt
        )
    {
        Auction storage auction = tokenIdToAuctions[contractAddr][_tokenId];
        require(_isOnAuction(auction), "This token is not in auction");
        return (
            auction.seller,
            auction.startingPrice,
            auction.endingPrice,
            auction.duration,
            auction.startedAt
        );
    }

    /// @dev Returns the current price of an auction.
    /// @param contractAddr - Address of current Smart Contract
    /// @param _tokenId - ID of the token price we are checking.
    function getCurrentPrice(address contractAddr, uint256 _tokenId)
        external
        view
        returns (uint256)
    {
        Auction storage auction = tokenIdToAuctions[contractAddr][_tokenId];
        require(_isOnAuction(auction), "This token is not in auction");
        return _currentPrice(auction);
    }

    function transfer(
        address contractAddr,
        address _receiver,
        uint256 _tokenId
    ) external virtual {
        require(
            _owns(contractAddr, msg.sender, _tokenId),
            "transfer caller is not owner"
        );
        _send(contractAddr, msg.sender, _receiver, _tokenId);
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function resume() external onlyOwner whenPaused {
        _unpause();
    }

    function setRoyalty(
        address contractAddr,
        address[] calldata dests,
        uint256[] calldata profits
    ) external onlyOwner {
        require(
            dests.length == profits.length,
            "Length of Addresses and Profits are different"
        );
        uint256 i;
        uint256 length = dests.length;
        uint256 sum = 0;
        for (i = 0; i < length; ++i) {
            sum += profits[i];
        }
        require(sum < 9500, "Total Sum of profit exceeds 95%");
        delete royalty[contractAddr];
        for (i = 0; i < length; ++i) {
            royalty[contractAddr].push(Royalty(dests[i], profits[i]));
        }
    }
}
