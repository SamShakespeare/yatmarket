// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

abstract contract IERC721Full is IERC721, IERC721Enumerable, IERC721Metadata {}

contract YATMarket is Ownable {
    IERC721Full nftContract;
    
    struct Bid {
        uint bidId;
        uint tokenId;
        uint bidPrice;
        address bidder;
        Status status;
    }

    struct Listing {
        bool active;
        uint256 listingId;
        uint256 tokenId;
        uint256 price;
        uint256 activeIndex; // index where the listing id is located on activeListings
        uint256 userActiveIndex; // index where the listing id is located on userActiveListings
        address owner;
        string tokenURI;
    }

    struct Purchase {
        Listing listing;
        address buyer;
    }

    enum Status {CANCELLED, ACTIVE, ACCEPTED}
    
    //map tokenIds to array of Bids
    mapping(uint256 => Bid[]) public bids;
    //map of tokenIds to listingIds
    mapping(uint256 => uint256) public tokenListings;

    uint256 private nextBidId;

    event BidCreated(
        uint256 indexed bidId,
        uint256 indexed tokenId,
        uint256 bid,
        address bidder,
        address owner,
        Status indexed status
    );

    event BidAccepted(uint256 indexed bidId);

    event BidStatusUpdated(uint256 indexed bidId, Status indexed status);

    event ListingCreated (
        bool indexed active,
        uint256 indexed listingId,
        uint256 indexed tokenId,
        uint256 price,
        address owner,
        string tokenURI
    );

    event ListingUpdated(uint256 listingId, uint256 price);
    event ListingCancelled(uint256 id, bool active);
    event ListingFilled(uint id, bool active, address buyer);
    event FilledListing(Purchase listing);

    Listing[] public listings;
    uint256[] public activeListings; // list of listingIDs which are active
    mapping(address => uint256[]) public userActiveListings; // list of listingIDs which are active
    
    uint256 public marketFeePercent = 0;

    uint256 public totalVolume = 0;
    uint256 public totalSales = 0;
    uint256 public highestSalePrice = 0;
    
    bool public isMarketOpen = false;
    bool public emergencyDelisting = false;

    constructor(
        address nft_address,
        uint256 market_fee
    ) {
        require(market_fee <= 100, "Give a percentage value from 0 to 100");

        nftContract = IERC721Full(nft_address);
        marketFeePercent = market_fee;

        //create Listing 0  
        Listing memory listing = Listing(
            false,
            0,
            0,
            0,
            0, // activeIndex
            0, // userActiveIndex
            msg.sender,
            ""
        );
        listings.push(listing);
    
    }

    function openMarket() external onlyOwner {
        isMarketOpen = true;
    }

    function closeMarket() external onlyOwner {
        isMarketOpen = false;
    }

    function allowEmergencyDelisting() external onlyOwner {
        emergencyDelisting = true;
    }

    function totalListings() external view returns (uint256) {
        return listings.length;
    }

    function totalActiveListings() external view returns (uint256) {
        return activeListings.length;
    }

    function getActiveListings(uint256 from, uint256 length)
        external
        view
        returns (Listing[] memory listing)
    {
        uint256 numActive = activeListings.length;
        if (from + length > numActive) {
            length = numActive - from;
        }

        Listing[] memory _listings = new Listing[](length);
        for (uint256 i = 0; i < length; i++) {
            Listing memory _l = listings[activeListings[from + i]];
            _l.tokenURI = nftContract.tokenURI(_l.tokenId);
            _listings[i] = _l;
        }
        return _listings;
    }

    function removeActiveListing(uint256 index) internal {
        uint256 numActive = activeListings.length;

        require(numActive > 0, "There are no active listings");
        require(index < numActive, "Incorrect index");

        activeListings[index] = activeListings[numActive - 1];
        listings[activeListings[index]].activeIndex = index;
        activeListings.pop();
    }

    function removeOwnerActiveListing(address owner, uint256 index) internal {
        uint256 numActive = userActiveListings[owner].length;

        require(numActive > 0, "There are no active listings for this user.");
        require(index < numActive, "Incorrect index");

        userActiveListings[owner][index] = userActiveListings[owner][
            numActive - 1
        ];
        listings[userActiveListings[owner][index]].userActiveIndex = index;
        userActiveListings[owner].pop();
    }

    function getMyActiveListingsCount() external view returns (uint256) {
        return userActiveListings[msg.sender].length;
    }

    function getMyActiveListings(uint256 from, uint256 length)
        external
        view
        returns (Listing[] memory listing)
    {
        uint256 numActive = userActiveListings[msg.sender].length;

        if (from + length > numActive) {
            length = numActive - from;
        }

        Listing[] memory myListings = new Listing[](length);

        for (uint256 i = 0; i < length; i++) {
            Listing memory _l = listings[
                userActiveListings[msg.sender][i + from]
            ];
            _l.tokenURI = nftContract.tokenURI(_l.tokenId);
            myListings[i] = _l;
        }
        return myListings;
    }

    function addListing(uint256 tokenId, uint256 price) external {
        require(msg.sender == owner() || isMarketOpen, "Market is closed.");
        uint256 ttlSupply = nftContract.totalSupply();
        require(tokenId < ttlSupply, "Invald tokenID");
        require(msg.sender == nftContract.ownerOf(tokenId), "Invalid owner");

        uint256 id = listings.length;
        Listing memory listing = Listing(
            true,
            id,
            tokenId,
            price,
            activeListings.length, // activeIndex
            userActiveListings[msg.sender].length, // userActiveIndex
            msg.sender,
            ""
        );

        listings.push(listing);
        userActiveListings[msg.sender].push(id);
        activeListings.push(id);
        tokenListings[listing.tokenId] = listing.listingId;

        //emit AddedListing(listing);
        emit ListingCreated (
            listings[id].active,
            listings[id].listingId,
            listings[id].tokenId,
            listings[id].price,
            listings[id].owner,
            nftContract.tokenURI(listings[id].tokenId)
        );

        nftContract.transferFrom(msg.sender, address(this), tokenId);
    }

    function updateListing(uint256 id, uint256 price) external {
        require(id < listings.length, "Invalid Listing");
        require(listings[id].active, "Listing no longer active");
        require(listings[id].owner == msg.sender, "Invalid Owner");

        listings[id].price = price;

        emit ListingUpdated(id, listings[id].price);
    }

    function cancelListing(uint256 id) external {
        require(id < listings.length, "Invalid Listing");
        Listing memory listing = listings[id];
        require(listing.active, "Listing no longer active");
        require(listing.owner == msg.sender, "Invalid Owner");

        removeActiveListing(listing.activeIndex);
        removeOwnerActiveListing(msg.sender, listing.userActiveIndex);

        listings[id].active = false;
        tokenListings[listing.tokenId] = 0;

        emit ListingCancelled(id, listings[id].active);

        nftContract.transferFrom(address(this), listing.owner, listing.tokenId);
    }

    function getTokenOwner(uint256 tokenId) public view returns (address){
        //is token (blueprint) listed
        uint256 listingId = tokenListings[tokenId];
        if (listingId == 0){
            return nftContract.ownerOf(tokenId);
        } else return listings[listingId].owner;
    }

    function placeBid(uint256 tokenId) external payable {
        address tokenOwner = getTokenOwner(tokenId);
        require(msg.sender != tokenOwner, "Can't place bid for own blueprint");
        uint256 ttlSupply = nftContract.totalSupply();
        require(tokenId < ttlSupply, "Invald tokenID");
        require(msg.value >= 0, "Must send value of bid");

        
        uint256 index = bids[tokenId].length;
        bids[tokenId].push(Bid(nextBidId, tokenId, msg.value, msg.sender, Status.ACTIVE));
        nextBidId++;

        emit BidCreated(
            bids[tokenId][index].bidId,
            bids[tokenId][index].tokenId,     
            bids[tokenId][index].bidPrice,
            bids[tokenId][index].bidder,
            tokenOwner,
            bids[tokenId][index].status
        );
    }

    function cancelBid (uint tokenId, uint256 bidId) external payable {
        require(bids[tokenId].length >= 1, "No Bids were Sent");
        require(msg.sender == bids[tokenId][bidId].bidder, "can only cancel own bid");
        require(bids[tokenId][bidId].status == Status.ACTIVE, "Not an active bid");
        uint256 bidAmount = bids[tokenId][bidId].bidPrice;
        bids[tokenId][bidId].status = Status.CANCELLED;

        emit BidStatusUpdated(
            bidId,
            bids[tokenId][bidId].status
        );
        //payable(msg.sender).transfer(bidAmount);
        (bool sent,) = payable(msg.sender).call{value: bidAmount}("");
        require(sent, "Failed to send value");
    }

    function acceptBid(uint tokenId, uint256 bidId) external {
        address tokenOwner = getTokenOwner(tokenId);
        require(msg.sender == tokenOwner, "Can only accept bid for own blueprint");
        require(bids[tokenId][bidId].status == Status.ACTIVE, "Not an active bid");
        uint256 bidAmount = bids[tokenId][bidId].bidPrice;
        address payable buyer = payable(bids[tokenId][bidId].bidder);
        bids[tokenId][bidId].status = Status.ACCEPTED;

        //check if this was an active listing
        uint256 tknListId = tokenListings[tokenId];
        if(tknListId > 0){
            Listing memory listing = listings[tknListId];
            listings[tknListId].active = false;
            tokenListings[tokenId] = 0;

            // Update active listings
            removeActiveListing(listing.activeIndex);
            removeOwnerActiveListing(listing.owner, listing.userActiveIndex);
        }

        uint256 market_cut = (bidAmount * marketFeePercent) / 100;
        uint256 seller_cut = bidAmount - market_cut;
        // Update global stats
        totalVolume += bidAmount;
        totalSales += 1;

        if (bidAmount > highestSalePrice) {
            highestSalePrice = bidAmount;
        }

        emit BidAccepted(bidId);

        //payable(msg.sender).transfer(seller_cut);
        (bool sent,) = payable(msg.sender).call{value: seller_cut}("");
        require(sent, "Failed to send value");
        nftContract.transferFrom(msg.sender, buyer, tokenId);
    }

    function fulfillListing(uint256[] calldata listingIds) external payable {
        uint256 remaingValue = msg.value;
        for(uint i=0; i < listingIds.length; i++){
            uint256 listingId = listingIds[i];
            require(listingId < listings.length, "Invalid Listing");
            Listing memory listing = listings[listingId];
            require(listing.active, "Listing not active");
            require(msg.sender != listing.owner, "Owner cannot buy own listing");
            require(remaingValue >= listing.price, "Did not send enough value");
            remaingValue -= listing.price;
            listings[listingId].active = false;
            tokenListings[listing.tokenId] = 0;
            // Update active listings
            removeActiveListing(listing.activeIndex);
            removeOwnerActiveListing(listing.owner, listing.userActiveIndex);
            // Update global stats
            totalVolume += listing.price;
            totalSales += 1;

            if (listing.price > highestSalePrice) {
                highestSalePrice = listing.price;
            }

            emit ListingFilled(
                listingId,
                listings[listingId].active,
                msg.sender
            );

            emit FilledListing(
                Purchase({listing: listings[listingId], buyer: msg.sender})
            );

            uint256 market_cut = (listing.price * marketFeePercent) / 100;
            uint256 seller_cut = listing.price - market_cut;
            //payable(listing.owner).transfer(seller_cut);
            (bool sent,) = payable(listing.owner).call{value: seller_cut}("");
            require(sent, "Failed to send value");
            nftContract.transferFrom(address(this), msg.sender, listing.tokenId);
        }
    }
    
    function adjustFees(uint256 newMarketFee) external onlyOwner {
        require(newMarketFee <= 100, "Give a percentage value from 0 to 100");
        marketFeePercent = newMarketFee;
    }

    function emergencyDelist(uint256 listingID) external {
        require(emergencyDelisting && !isMarketOpen, "Only in emergency.");
        require(listingID < listings.length, "Invalid Listing");
        Listing memory listing = listings[listingID];

        nftContract.transferFrom(address(this), listing.owner, listing.tokenId);
    }

     function withdrawableBalance() public view returns (uint256 value) {
        return address(this).balance;
    }

    function withdrawBalance() external onlyOwner {
        uint256 withdrawable = withdrawableBalance();
        payable(_msgSender()).transfer(withdrawable);
    }

    function emergencyWithdraw() external onlyOwner {
        payable(_msgSender()).transfer(address(this).balance);
    }

    receive() external payable {} // solhint-disable-line

    fallback() external payable {} // solhint-disable-line
}
