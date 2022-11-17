// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ClockSaleBase.sol";

/// @title Clock sale for non-fungible tokens.
/// @notice We omit a fallback function to prevent accidental sends to this contract.
contract ClockSale is Pausable, ClockSaleBase, Ownable {
    /// @dev The ERC-165 interface signature for ERC-721.
    ///  Ref: https://github.com/ethereum/EIPs/issues/165
    ///  Ref: https://github.com/ethereum/EIPs/issues/721
    // bytes4 constant InterfaceSignature_ERC721 = bytes4(0x9a20483d);

    /// @dev Remove all Ether from the contract, which is the owner's cuts
    ///  as well as any Ether sent directly to the contract address.
    ///  Always transfers to the NFT contract, but can be called either by
    ///  the owner or the NFT contract.

    /// @dev Creates and begins a new sale.
    /// @param contractAddr - Address of current Smart Contract
    /// @param _tokenId - ID of token to sale, sender must be owner.
    /// @param price - Price of item (in wei) at beginning of sale.
    ///  price and ending price (in seconds).
    function createSale(
        address contractAddr,
        uint256 _tokenId,
        uint256 price
    )
        external
        virtual
        exists(contractAddr)
        verified(contractAddr)
        whenNotPaused
        owningToken(contractAddr, _tokenId)
    {
        // Sanity check that no inputs overflow how many bits we've allocated
        // to store them in the sale struct.
        require(price == uint256(uint128(price)));

        _escrow(contractAddr, msg.sender, _tokenId);
        Sale memory sale = Sale(msg.sender, uint128(price), block.timestamp);
        _addSale(contractAddr, _tokenId, sale);
    }

    function createAuction(
        address contractAddr,
        uint256 _tokenId,
        uint256 price,
        uint256 duration
    )
        external
        virtual
        exists(contractAddr)
        verified(contractAddr)
        whenNotPaused
        owningToken(contractAddr, _tokenId)
    {
        // Sanity check that no inputs overflow how many bits we've allocated
        // to store them in the sale struct.
        require(price == uint256(uint128(price)));

        _escrow(contractAddr, msg.sender, _tokenId);
        Auction memory auction = Auction(
            msg.sender,
            uint128(price),
            duration,
            block.timestamp
        );
        _addAuction(contractAddr, _tokenId, auction);
    }

    /// @dev Buys on an open sale, completing the sale and transferring
    ///  ownership of the NFT if enough Ether is supplied.
    /// @param contractAddr - Address of current Smart Contract
    /// @param tokenId - ID of token to buy on.
    function buy(address contractAddr, uint256 tokenId)
        external
        payable
        virtual
        exists(contractAddr)
        whenNotPaused
        onSale(contractAddr, tokenId)
        onlyBuyer(contractAddr, tokenId)
    {
        // _buy will throw if the buy or funds transfer fails
        uint256 price = _buy(contractAddr, tokenId, msg.value);
        _transfer(contractAddr, msg.sender, tokenId);
        // Tell the world!
        emit SaleSuccessful(contractAddr, tokenId, price, msg.sender);
    }

    /// @dev Cancels an sale that hasn't been won yet.
    ///  Returns the NFT to original owner.
    /// @notice This is a state-modifying function that can
    ///  be called while the contract is paused.
    /// @param contractAddr - Address of current Smart Contract
    /// @param _tokenId - ID of token on sale
    function cancelSale(address contractAddr, uint256 _tokenId)
        external
        exists(contractAddr)
        onSale(contractAddr, _tokenId)
        onlySeller(contractAddr, _tokenId)
    {
        _cancelSale(contractAddr, _tokenId);
    }

    function cancelAuction(address contractAddr, uint256 _tokenId)
        external
        exists(contractAddr)
        onAuction(contractAddr, _tokenId)
        onlyAuctioneer(contractAddr, _tokenId)
    {
        _cancelAuction(contractAddr, _tokenId);
    }

    /// @dev Cancels an sale when the contract is paused.
    ///  Only the owner may do this, and NFTs are returned to
    ///  the seller. This should only be used in emergencies.
    /// @param contractAddr - Address of current Smart Contract
    /// @param _tokenId - ID of the NFT on sale to cancel.
    function cancelSaleWhenPaused(address contractAddr, uint256 _tokenId)
        external
        exists(contractAddr)
        whenPaused
        onlyOwner
        onSale(contractAddr, _tokenId)
    {
        _cancelSale(contractAddr, _tokenId);
    }

    /// @dev Returns sale info for an NFT on sale.
    /// @param contractAddr - Address of current Smart Contract
    /// @param _tokenId - ID of NFT on sale.
    function getSale(address contractAddr, uint256 _tokenId)
        external
        view
        exists(contractAddr)
        onSale(contractAddr, _tokenId)
        returns (address seller, uint256 price)
    {
        Sale storage sale = tokenIdToSales[contractAddr][_tokenId];
        return (sale.seller, sale.price);
    }

    function getAuction(address contractAddr, uint256 _tokenId)
        external
        view
        exists(contractAddr)
        onAuction(contractAddr, _tokenId)
        returns (
            address auctioneer,
            uint256 price,
            uint256 startedAt,
            uint256 duration
        )
    {
        Auction storage auction = tokenIdToAuctions[contractAddr][_tokenId];
        return (
            auction.auctioneer,
            auction.price,
            auction.startedAt,
            auction.duration
        );
    }

    /// @dev Returns the current price of an sale.
    /// @param contractAddr - Address of current Smart Contract
    /// @param _tokenId - ID of the token price we are checking.
    function getCurrentPrice(address contractAddr, uint256 _tokenId)
        external
        view
        exists(contractAddr)
        onSale(contractAddr, _tokenId)
        returns (uint256)
    {
        return tokenIdToSales[contractAddr][_tokenId].price;
    }

    function transfer(
        address contractAddr,
        address _receiver,
        uint256 _tokenId
    )
        external
        virtual
        exists(contractAddr)
        whenNotPaused
        owningToken(contractAddr, _tokenId)
    {
        _send(contractAddr, msg.sender, _receiver, _tokenId);
    }

    function createOffer(address contractAddr, uint256 tokenId)
        external
        payable
        exists(contractAddr)
        onSale(contractAddr, tokenId)
        onlyBuyer(contractAddr, tokenId)
        hasNoOffer(contractAddr, tokenId)
    {
        require(
            msg.value < tokenIdToSales[contractAddr][tokenId].price,
            "Price should be lower than listing price"
        );
        _createOffer(contractAddr, tokenId, msg.sender, msg.value);
    }

    function bid(address contractAddr, uint256 tokenId)
        external
        payable
        exists(contractAddr)
        onAuction(contractAddr, tokenId)
        onlyBidder(contractAddr, tokenId)
        hasNoBid(contractAddr, tokenId)
    {
        require(
            block.timestamp <=
                tokenIdToAuctions[contractAddr][tokenId].startedAt +
                    tokenIdToAuctions[contractAddr][tokenId].duration,
            "Auction is already finished"
        );
        require(
            msg.value > tokenIdToAuctions[contractAddr][tokenId].price,
            "Bid in current price range"
        );
        uint256 bidLength = bids[contractAddr][tokenId].length;
        require(
            bidLength == 0 ||
                bids[contractAddr][tokenId][bidLength - 1].price < msg.value,
            "You should bid on higher price"
        );
        _bid(contractAddr, tokenId, msg.sender, msg.value);
    }

    function getOffers(address contractAddr, uint256 tokenId)
        external
        view
        exists(contractAddr)
        onSale(contractAddr, tokenId)
        returns (
            address[] memory,
            uint256[] memory,
            uint256[] memory
        )
    {
        uint256 length = offers[contractAddr][tokenId].length;
        address[] memory offerers = new address[](length);
        uint256[] memory prices = new uint256[](length);
        uint256[] memory times = new uint256[](length);
        uint256 i;
        for (i = 0; i < length; ++i) {
            offerers[i] = offers[contractAddr][tokenId][i].offerer;
            prices[i] = offers[contractAddr][tokenId][i].price;
            times[i] = offers[contractAddr][tokenId][i].time;
        }
        return (offerers, prices);
    }

    function getBids(address contractAddr, uint256 tokenId)
        external
        view
        exists(contractAddr)
        onAuction(contractAddr, tokenId)
        returns (
            address[] memory,
            uint256[] memory,
            uint256[] memory
        )
    {
        uint256 length = bids[contractAddr][tokenId].length;
        address[] memory bidders = new address[](length);
        uint256[] memory prices = new uint256[](length);
        uint256[] memory times = new uint256[](length);
        uint256 i;
        for (i = 0; i < length; ++i) {
            bidders[i] = bids[contractAddr][tokenId][i].bidder;
            prices[i] = bids[contractAddr][tokenId][i].price;
            times[i] = bids[contractAddr][tokenIdToAuctions][i].time;
        }
        return (bidders, prices, times);
    }

    function cancelOffer(address contractAddr, uint256 tokenId)
        external
        exists(contractAddr)
        onSale(contractAddr, tokenId)
        hasOffer(contractAddr, tokenId)
    {
        uint256 length = offers[contractAddr][tokenId].length;
        uint256 i;
        for (
            i = 0;
            i < length &&
                offers[contractAddr][tokenId][i].offerer != msg.sender;
            ++i
        ) {}
        require(i < length, "You haven't got offer");
        payable(address(msg.sender)).transfer(
            offers[contractAddr][tokenId][i].price
        );
        for (; i < length - 1; ++i) {
            offers[contractAddr][tokenId][i] = offers[contractAddr][tokenId][
                i + 1
            ];
        }
        offers[contractAddr][tokenId].pop();
        emit OfferCanceled(contractAddr, tokenId, msg.sender);
    }

    function cancelBid(address contractAddr, uint256 tokenId)
        external
        exists(contractAddr)
        onAuction(contractAddr, tokenId)
        hasBid(contractAddr, tokenId)
    {
        uint256 length = bids[contractAddr][tokenId].length;
        uint256 i;
        for (
            i = 0;
            i < length && bids[contractAddr][tokenId][i].bidder != msg.sender;
            ++i
        ) {}
        require(i < length, "You haven't got bid");
        payable(address(msg.sender)).transfer(
            bids[contractAddr][tokenId][i].price
        );
        for (; i < length - 1; ++i) {
            bids[contractAddr][tokenId][i] = bids[contractAddr][tokenId][i + 1];
        }
        bids[contractAddr][tokenId].pop();
        emit BidCanceled(contractAddr, tokenId, msg.sender);
    }

    function setAddressesContractAddr(address contractAddr) external {
        addressesContractAddr = contractAddr;
    }
}
