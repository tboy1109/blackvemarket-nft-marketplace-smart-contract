// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "./ERC721Royal.sol";

/// @title Auction Core
/// @dev Contains models, variables, and internal methods for the auction.
/// @notice We omit a fallback function to prevent accidental sends to this contract.
contract ClockAuctionBase {
    // Represents an auction on an NFT
    struct Auction {
        // Address of Smart Contract
        // address contractAddr;
        // Current owner of NFT
        address seller;
        // Price (in wei) at beginning of auction
        uint128 startingPrice;
        // Price (in wei) at end of auction
        uint128 endingPrice;
        // Duration (in seconds) of auction
        uint64 duration;
        // Time when auction started
        // NOTE: 0 if this auction has been concluded
        uint64 startedAt;
    }

    struct Royalty {
        address destination;
        uint256 profit;
    }

    // Map from token ID to their corresponding auction.
    mapping(address => mapping(uint256 => Auction)) tokenIdToAuctions;

    // Save Sale Token Ids by Contract Addresses
    mapping(address => uint256[]) public saleTokenIds;
    // Sale Token Ids by Seller Addresses
    mapping(address => mapping(address => uint256[]))
        private saleTokenIdsBySeller;
    //Royalty
    mapping(address => Royalty[]) royalty;

    address public charityAddr = 0x10B708FF9F5d20109CfA91e729a84404351c86C7;
    address public teamAddr = 0x8E0AFCE03755eDA5A0fC6fA93f15835EaA1867C6;
    address public devAddr = 0x30e5dD834FF5855b07fAb357F74F9b0Ab2744f6e;

    event AuctionCreated(
        address contractAddr,
        uint256 tokenId,
        uint256 startingPrice,
        uint256 endingPrice,
        uint256 duration
    );
    event AuctionSuccessful(
        address contractAddr,
        uint256 tokenId,
        uint256 totalPrice,
        address winner
    );
    event AuctionCancelled(address contractAddr, uint256 tokenId);

    /// @dev Returns true if the claimant owns the token.
    /// @param contractAddr - Address of current Smart Contract
    /// @param _claimant - Address claiming to own the token.
    /// @param _tokenId - ID of token whose ownership to verify.
    function _owns(
        address contractAddr,
        address _claimant,
        uint256 _tokenId
    ) internal view returns (bool) {
        ERC721 nftContract = ERC721(contractAddr);
        return (nftContract.ownerOf(_tokenId) == _claimant);
    }

    /// @dev Adds an auction to the list of open auctions. Also fires the
    ///  AuctionCreated event.
    /// @param contractAddr - Address of current Smart Contract
    /// @param _tokenId The ID of the token to be put on auction.
    /// @param _auction Auction to add.
    function _addAuction(
        address contractAddr,
        uint256 _tokenId,
        Auction memory _auction
    ) internal {
        // Require that all auctions have a duration of
        // at least one minute. (Keeps our math from getting hairy!)

        tokenIdToAuctions[contractAddr][_tokenId] = _auction;
        saleTokenIds[contractAddr].push(_tokenId);
        saleTokenIdsBySeller[_auction.seller][contractAddr].push(_tokenId);

        emit AuctionCreated(
            contractAddr,
            uint256(_tokenId),
            uint256(_auction.startingPrice),
            uint256(_auction.endingPrice),
            uint256(_auction.duration)
        );
    }

    /// @dev Cancels an auction unconditionally.
    /// @param contractAddr - Address of current Smart Contract
    /// @param _tokenId - ID of the token price we are canceling.
    function _cancelAuction(address contractAddr, uint256 _tokenId) internal {
        _transfer(
            contractAddr,
            tokenIdToAuctions[contractAddr][_tokenId].seller,
            _tokenId
        );
        _removeAuction(contractAddr, _tokenId);
        emit AuctionCancelled(contractAddr, _tokenId);
    }

    /// @dev Computes the price and transfers winnings.
    /// Does NOT transfer ownership of token.
    function _bid(
        address contractAddr,
        uint256 _tokenId,
        uint256 _bidAmount
    ) internal returns (uint256) {
        // Get a reference to the auction struct
        Auction storage auction = tokenIdToAuctions[contractAddr][_tokenId];

        // Explicitly check that this auction is currently live.
        // (Because of how Ethereum mappings work, we can't just count
        // on the lookup above failing. An invalid _tokenId will just
        // return an auction object that is all zeros.)
        require(_isOnAuction(auction), "This token is not at auction");

        // Check that the bid is greater than or equal to the current price
        uint256 price = _currentPrice(auction);
        require(
            _bidAmount >= price,
            "Bid price should be bigger than current price"
        );

        // Grab a reference to the seller before the auction struct
        // gets deleted.

        address seller = auction.seller;

        // The bid is good! Remove the auction before sending the fees
        // to the sender so we can't have a reentrancy attack.
        _removeAuction(contractAddr, _tokenId);

        // Transfer proceeds to seller (if there are any!)
        if (price > 0) {
            // Calculate the auctioneer's cut.
            // (NOTE: _computeCut() is guaranteed to return a
            // value <= price, so this subtraction can't go negative.)
            // uint256 auctioneerCut = _computeCut(price);
            // uint256 sellerProceeds = price - auctioneerCut;
            uint256 length = royalty[contractAddr].length;
            uint256 sum = 0;
            uint256 i;
            for (i = 0; i < length; ++i) {
                sum += royalty[contractAddr][i].profit;
            }
            uint256 devProfit = _bidAmount -
                (price * (9500 - sum)) /
                10000 -
                (price * sum) /
                10000 -
                price /
                100 -
                price /
                50;
            // NOTE: Doing a transfer() in the middle of a complex
            // method like this is generally discouraged because of
            // reentrancy attacks and DoS attacks if the seller is
            // a contract with an invalid fallback function. We explicitly
            // guard against reentrancy attacks by removing the auction
            // before calling transfer(), and the only thing the seller
            // can DoS is the sale of their own asset! (And if it's an
            // accident, they can call cancelAuction(). )
            payable(charityAddr).transfer(_bidAmount / 100);
            payable(teamAddr).transfer(_bidAmount / 50);
            payable(devAddr).transfer(devProfit);
            payable(seller).transfer((price * (9500 - sum)) / 10000);
            for (i = 0; i < length; ++i) {
                payable(royalty[contractAddr][i].destination).transfer(
                    (_bidAmount * royalty[contractAddr][i].profit) / 10000
                );
            }
        }

        // Tell the world!
        emit AuctionSuccessful(contractAddr, _tokenId, price, msg.sender);

        return price;
    }

    function _bidRoyalty(
        address contractAddr,
        address creator,
        uint256 _tokenId,
        uint256 _bidAmount
    ) internal returns (uint256) {
        // Get a reference to the auction struct
        Auction storage auction = tokenIdToAuctions[contractAddr][_tokenId];
        ERC721Royal curContract = ERC721Royal(contractAddr);
        uint8 nftRoyalty = curContract.getRoyalty(_tokenId);

        // Explicitly check that this auction is currently live.
        // (Because of how Ethereum mappings work, we can't just count
        // on the lookup above failing. An invalid _tokenId will just
        // return an auction object that is all zeros.)
        require(_isOnAuction(auction), "This token is not at auction");

        // Check that the bid is greater than or equal to the current price
        uint256 price = _currentPrice(auction);
        require(
            _bidAmount >= price,
            "Bid price should be bigger than current price"
        );

        // Grab a reference to the seller before the auction struct
        // gets deleted.
        address seller = auction.seller;

        // The bid is good! Remove the auction before sending the fees
        // to the sender so we can't have a reentrancy attack.
        _removeAuction(contractAddr, _tokenId);

        // Transfer proceeds to seller (if there are any!)
        if (price > 0) {
            // Calculate the auctioneer's cut.
            // (NOTE: _computeCut() is guaranteed to return a
            // value <= price, so this subtraction can't go negative.)
            // uint256 auctioneerCut = _computeCut(price);
            // uint256 sellerProceeds = price - auctioneerCut;
            uint256 sellerProfit = (price * (95 - nftRoyalty)) / 100;
            uint256 charityProfit = price / 100;
            uint256 teamProfit = price / 50;
            uint256 creatorProfit = (price * nftRoyalty) / 100;
            uint256 devProfit = _bidAmount -
                sellerProfit -
                charityProfit -
                teamProfit -
                creatorProfit;
            // NOTE: Doing a transfer() in the middle of a complex
            // method like this is generally discouraged because of
            // reentrancy attacks and DoS attacks if the seller is
            // a contract with an invalid fallback function. We explicitly
            // guard against reentrancy attacks by removing the auction
            // before calling transfer(), and the only thing the seller
            // can DoS is the sale of their own asset! (And if it's an
            // accident, they can call cancelAuction(). )
            payable(charityAddr).transfer(charityProfit);
            payable(teamAddr).transfer(teamProfit);
            payable(devAddr).transfer(devProfit);
            payable(seller).transfer(sellerProfit);
            payable(creator).transfer(creatorProfit);
        }

        // Tell the world!
        emit AuctionSuccessful(contractAddr, _tokenId, price, msg.sender);

        return price;
    }

    /// @dev Removes an auction from the list of open auctions.
    /// @param contractAddr - Address of current Smart Contract
    /// @param _tokenId - ID of NFT on auction.
    function _removeAuction(address contractAddr, uint256 _tokenId) internal {
        uint256 i;
        uint256 length = saleTokenIds[contractAddr].length;
        for (i = 0; i < length; ++i) {
            if (saleTokenIds[contractAddr][i] == _tokenId) {
                break;
            }
        }
        if (i < length - 1) {
            saleTokenIds[contractAddr][i] = saleTokenIds[contractAddr][
                length - 1
            ];
        }
        saleTokenIds[contractAddr].pop();
        Auction storage auction = tokenIdToAuctions[contractAddr][_tokenId];
        length = saleTokenIdsBySeller[auction.seller][contractAddr].length;
        uint256 index;
        for (
            index = 0;
            saleTokenIdsBySeller[auction.seller][contractAddr][index] !=
            _tokenId;
            ++index
        ) {}
        saleTokenIdsBySeller[auction.seller][contractAddr][
            index
        ] = saleTokenIdsBySeller[auction.seller][contractAddr][length - 1];
        saleTokenIdsBySeller[auction.seller][contractAddr].pop();
        delete tokenIdToAuctions[contractAddr][_tokenId];
    }

    function getRoyalty(address contractAddr)
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        uint256 length = royalty[contractAddr].length;
        address[] memory dests = new address[](length);
        uint256[] memory profits = new uint256[](length);
        uint256 i;
        for (i = 0; i < length; ++i) {
            dests[i] = royalty[contractAddr][i].destination;
            profits[i] = royalty[contractAddr][i].profit;
        }
        return (dests, profits);
    }

    /// @dev Returns true if the NFT is on auction.
    /// @param _auction - Auction to check.
    function _isOnAuction(Auction storage _auction)
        internal
        view
        returns (bool)
    {
        return (_auction.startedAt > 0);
    }

    /// @dev Returns current price of an NFT on auction. Broken into two
    ///  functions (this one, that computes the duration from the auction
    ///  structure, and the other that does the price computation) so we
    ///  can easily test that the price computation works correctly.
    function _currentPrice(Auction storage _auction)
        internal
        view
        returns (uint256)
    {
        uint256 secondsPassed = 0;

        // A bit of insurance against negative values (or wraparound).
        // Probably not necessary (since Ethereum guarnatees that the
        // now variable doesn't ever go backwards).
        if (block.timestamp > _auction.startedAt) {
            secondsPassed = block.timestamp - _auction.startedAt;
        }

        return
            _computeCurrentPrice(
                _auction.startingPrice,
                _auction.endingPrice,
                _auction.duration,
                secondsPassed
            );
    }

    /// @dev Computes the current price of an auction. Factored out
    ///  from _currentPrice so we can run extensive unit tests.
    ///  When testing, make this function public and turn on
    ///  `Current price computation` test suite.
    function _computeCurrentPrice(
        uint256 _startingPrice,
        uint256 _endingPrice,
        uint256 _duration,
        uint256 _secondsPassed
    ) internal pure returns (uint256) {
        // NOTE: We don't use SafeMath (or similar) in this function because
        //  all of our public functions carefully cap the maximum values for
        //  time (at 64-bits) and currency (at 128-bits). _duration is
        //  also known to be non-zero (see the require() statement in
        //  _addAuction())
        if (_secondsPassed >= _duration) {
            // We've reached the end of the dynamic pricing portion
            // of the auction, just return the end price.
            return _endingPrice;
        } else {
            // Starting price can be higher than ending price (and often is!), so
            // this delta can be negative.
            int256 totalPriceChange = int256(_endingPrice) -
                int256(_startingPrice);

            // This multiplication can't overflow, _secondsPassed will easily fit within
            // 64-bits, and totalPriceChange will easily fit within 128-bits, their product
            // will always fit within 256-bits.
            int256 currentPriceChange = (totalPriceChange *
                int256(_secondsPassed)) / int256(_duration);

            // currentPriceChange can be negative, but if so, will have a magnitude
            // less that _startingPrice. Thus, this result will always end up positive.
            int256 currentPrice = int256(_startingPrice) + currentPriceChange;

            return uint256(currentPrice);
        }
    }

    /// @param contractAddr - Address of current Smart Contract
    function getSaleTokens(address contractAddr)
        public
        view
        returns (uint256[] memory)
    {
        return saleTokenIds[contractAddr];
    }

    /// @param contractAddr - Address of current Smart Contract
    function getAuctionCnt(address contractAddr) public view returns (uint256) {
        return saleTokenIds[contractAddr].length;
    }

    /// @param contractAddr - Address of current Smart Contract
    function balanceOf(address contractAddr, address owner)
        public
        view
        returns (uint256)
    {
        ERC721 nftContract = ERC721(contractAddr);
        return nftContract.balanceOf(owner);
    }

    /// @param contractAddr - Address of current Smart Contract
    /// @param index - Index of token
    function tokenOfOwnerByIndex(
        address contractAddr,
        address owner,
        uint256 index
    ) public view returns (uint256) {
        ERC721Enumerable nftContract = ERC721Enumerable(contractAddr);
        return nftContract.tokenOfOwnerByIndex(owner, index);
    }

    function ownerOf(address contractAddr, uint256 _tokenId)
        public
        view
        returns (address)
    {
        ERC721Enumerable nftContract = ERC721Enumerable(contractAddr);
        return nftContract.ownerOf(_tokenId);
    }

    /// @param contractAddr - Address of current Smart Contract
    function tokenURI(address contractAddr, uint256 tokenId)
        public
        view
        returns (string memory)
    {
        ERC721 nftContract = ERC721(contractAddr);
        return nftContract.tokenURI(tokenId);
    }

    function getSaleTokensBySeller(address seller, address contractAddr)
        public
        view
        returns (uint256[] memory)
    {
        return saleTokenIdsBySeller[seller][contractAddr];
    }

    /// @dev Escrows the NFT, assigning ownership to this contract.
    /// Throws if the escrow fails.
    /// @param _owner - Current owner address of token to escrow.
    /// @param _tokenId - ID of token whose approval to verify.
    function _escrow(
        address contractAddr,
        address _owner,
        uint256 _tokenId
    ) internal {
        // it will throw if transfer fails
        ERC721 nftContract = ERC721(contractAddr);
        nftContract.transferFrom(_owner, address(this), _tokenId);
    }

    function _transfer(
        address contractAddr,
        address _receiver,
        uint256 _tokenId
    ) internal {
        // it will throw if transfer fails
        ERC721 nftContract = ERC721(contractAddr);
        nftContract.transferFrom(address(this), _receiver, _tokenId);
    }

    function _send(
        address contractAddr,
        address _sender,
        address _receiver,
        uint256 _tokenId
    ) internal {
        ERC721 nftContract = ERC721(contractAddr);
        nftContract.transferFrom(_sender, _receiver, _tokenId);
    }
}
