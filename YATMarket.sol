// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

abstract contract IERC721Full is IERC721, IERC721Enumerable, IERC721Metadata {}

interface IERC2981Royalties {
    function royaltyInfo(uint256 _tokenId, uint256 _value)
        external
        view
        returns (address _receiver, uint256 _royaltyAmount);
}

library MrktStructs{
    struct Bid {
        uint id;
        uint bidPrice;
        address bidder;
    }

    struct Listing {
        bool active;
        uint256 id;
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

    function deleteBid (Bid[] storage _bids, uint256 bidId) public {
        require(_bids[bidId].bidPrice != 0, "No bid to cancel");
        delete _bids[bidId];
    }

    function createBid (Bid[] storage _bids, uint256 _bidPrice) public {
        uint bidId = _bids.length;
        if (bidId >= 1) require(_bids[bidId-1].bidPrice < _bidPrice, "Bid not high enough");
        require(msg.value >= _bidPrice, "Value sent less than bid");
        _bids.push(Bid(bidId, _bidPrice, msg.sender));
    }

    function getBids(Bid[] storage bidsArray)
        public
        view
        returns (Bid[] memory _bds)
    {
        Bid[] memory _bids = new Bid[](bidsArray.length);
        for (uint256 i = 0; i <= bidsArray.length-1; i++) {  
            _bids[i] = bidsArray[i];
        }

        return _bids;
    }
}

contract YATMarket is Ownable {
    IERC721Full nftContract;
    IERC2981Royalties royaltyInterface;
    uint256 immutable TOTAL_NFTS_COUNT;
    using MrktStructs for MrktStructs.Bid[];

    mapping(uint256 => MrktStructs.Bid[]) public bids;

    event BidCreated(
        uint256 listingId,
        uint256 bidId,
        uint256 bid,
        address bidder
    );

    event AddedListing(MrktStructs.Listing listing);
    event UpdateListing(MrktStructs.Listing listing);
    event FilledListing(MrktStructs.Purchase listing);
    event CanceledListing(MrktStructs.Listing listing);

    MrktStructs.Listing[] public listings;
    uint256[] public activeListings; // list of listingIDs which are active
    mapping(address => uint256[]) public userActiveListings; // list of listingIDs which are active

    mapping(uint256 => uint256) public communityRewards;

    uint256 public communityHoldings = 0;
    uint256 public communityFeePercent = 0;
    uint256 public marketFeePercent = 0;

    uint256 public totalVolume = 0;
    uint256 public totalSales = 0;
    uint256 public highestSalePrice = 0;
    uint256 public totalGivenRewardsPerToken = 0;

    bool public isMarketOpen = false;
    bool public emergencyDelisting = false;

    constructor(
        address nft_address,
        uint256 dist_fee,
        uint256 market_fee,
        uint256 total_nft_count
    ) {
        require(dist_fee <= 100, "Give a percentage value from 0 to 100");
        require(market_fee <= 100, "Give a percentage value from 0 to 100");

        nftContract = IERC721Full(nft_address);
        royaltyInterface = IERC2981Royalties(nft_address);

        communityFeePercent = dist_fee;
        marketFeePercent = market_fee;
        TOTAL_NFTS_COUNT = total_nft_count;
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
        returns (MrktStructs.Listing[] memory listing)
    {
        uint256 numActive = activeListings.length;
        if (from + length > numActive) {
            length = numActive - from;
        }

        MrktStructs.Listing[] memory _listings = new MrktStructs.Listing[](length);
        for (uint256 i = 0; i < length; i++) {
            MrktStructs.Listing memory _l = listings[activeListings[from + i]];
            _l.tokenURI = nftContract.tokenURI(_l.tokenId);
            _listings[i] = _l;
        }
        return _listings;
    }

    function removeActiveListing(uint256 index) internal {
        uint256 numActive = activeListings.length;
        require(numActive > 0, "There are no active listings");
        require(index < numActive, "Incorrect index");

        activeListings[index] = activeListings[activeListings.length - 1];
        listings[activeListings[index]].activeIndex = index;
        activeListings.pop();
    }

    function removeOwnerActiveListing(address owner, uint256 index) internal {
        uint256 numActive = userActiveListings[owner].length;
        require(numActive > 0, "No active listings for this user.");
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
        returns (MrktStructs.Listing[] memory listing)
    {
        uint256 numActive = userActiveListings[msg.sender].length;

        if (from + length > numActive) {
            length = numActive - from;
        }

        MrktStructs.Listing[] memory myListings = new MrktStructs.Listing[](length);

        for (uint256 i = 0; i < length; i++) {
            MrktStructs.Listing memory _l = listings[
                userActiveListings[msg.sender][i + from]
            ];
            _l.tokenURI = nftContract.tokenURI(_l.tokenId);
            myListings[i] = _l;
        }
        return myListings;
    }

    function addListing(uint256 tokenId, uint256 price) external {
        require(isMarketOpen, "Market is closed.");
        require(
            tokenId < TOTAL_NFTS_COUNT,
            "Invalid token Id"
        );
        require(msg.sender == nftContract.ownerOf(tokenId), "Invalid owner");

        uint256 id = listings.length;
        MrktStructs.Listing memory listing = MrktStructs.Listing({
            active: true,
            id: id,
            tokenId: tokenId,
            price: price,
            activeIndex: activeListings.length, // activeIndex
            userActiveIndex: userActiveListings[msg.sender].length, // userActiveIndex
            owner: msg.sender,
            tokenURI: ""
        });

        listings.push(listing);
        userActiveListings[msg.sender].push(id);
        activeListings.push(id);

        emit AddedListing(listing);

        nftContract.transferFrom(msg.sender, address(this), tokenId);
    }

    function updateListing(uint256 id, uint256 price) external {
        require(id < listings.length, "Invalid Listing");
        require(listings[id].active, "Listing not active");
        require(listings[id].owner == msg.sender, "Invalid Owner");

        listings[id].price = price;
        emit UpdateListing(listings[id]);
    }

    function cancelListing(uint256 id) external {
        require(id < listings.length, "Invalid Listing");
        MrktStructs.Listing memory listing = listings[id];
        require(listing.active, "Listing not active");
        require(listing.owner == msg.sender, "Invalid Owner");

        removeActiveListing(listing.activeIndex);
        removeOwnerActiveListing(msg.sender, listing.userActiveIndex);

        listings[id].active = false;

        emit CanceledListing(listing);

        nftContract.transferFrom(address(this), listing.owner, listing.tokenId);
    }

    function placeBid(uint256 listingId, uint256 _bidPrice) external payable {
        //uint256 bidId = bids[id].length;
        require(listings[listingId].active, "Listing not active");
        require(listings[listingId].owner != msg.sender, "Cant bid on own listing");
        
        //MrktStructs.createBid(bids[id], id, _bidPrice);
        bids[listingId].createBid(_bidPrice);
        
        emit BidCreated(
            listingId,     
            bids[listingId].length-1,
            _bidPrice,
            msg.sender
        );
    }

    function fulfillListing(uint256[] calldata listingIds, bool bidAccepted) external payable {
        for(uint i=0; i < listingIds.length; i++){
            uint256 listingId = listingIds[i];
            require(listingId < listings.length, "Invalid Listing");
            MrktStructs.Listing memory listing = listings[listingId];
            require(bidAccepted || msg.sender != listing.owner, "Owner cannot buy own listing");
            require(!bidAccepted || msg.sender == listing.owner, "Can only accept bid for own listing");
            require(listing.active, "Listing not active");

            uint256 price;
            address buyer;

            if(bidAccepted) {
                price = bids[listingId][bids[listingId].length-1].bidPrice;
                buyer = bids[listingId][bids[listingId].length-1].bidder;
            } else {
                price = listing.price;
                buyer = msg.sender;
            }
            
            (address originalMinter, uint256 royaltyAmount) = royaltyInterface
                .royaltyInfo(listing.tokenId, price);
            uint256 community_cut = (price * communityFeePercent) / 100;
            uint256 market_cut = (price * marketFeePercent) / 100;
            uint256 holder_cut = price -
                royaltyAmount -
                community_cut -
                market_cut;

            listings[listingId].active = false;

            // Update active listings
            removeActiveListing(listing.activeIndex);
            removeOwnerActiveListing(listing.owner, listing.userActiveIndex);

            // Update global stats
            totalVolume += price;
            totalSales += 1;

            if (price > highestSalePrice) {
                highestSalePrice = price;
            }

            uint256 perToken = community_cut / TOTAL_NFTS_COUNT;
            totalGivenRewardsPerToken += perToken;
            communityHoldings += (perToken) * TOTAL_NFTS_COUNT;

            emit FilledListing(
                MrktStructs.Purchase({listing: listings[listingId], buyer: buyer})
            );

            //cancel winning bid
            delete bids[listingId][bids[listingId].length-1];
            //now losing bids
            //must be >=1 bid for returnable bids to exist
            if(bids[listingId].length>=1){
                //return bids 1 by 1
                for(uint ii=bids[listingId].length; ii>0; i--){
                    MrktStructs.deleteBid(bids[listingId], ii-1);
                }
            }
            payable(listing.owner).transfer(holder_cut);
            payable(originalMinter).transfer(royaltyAmount);
            nftContract.transferFrom(address(this), buyer, listing.tokenId);
        }
    }

    function cancelBid(uint256 listingId, uint256 bidId) external {
        require(bids[listingId].length >= 1, "No bids for this listing");
        require(bids[listingId][bidId].bidder == msg.sender, "Can only cancel own bid");
        MrktStructs.deleteBid(bids[listingId], bidId);
        payable(bids[listingId][bidId].bidder).transfer(bids[listingId][bidId].bidPrice);
    }

    function getRewards() external view returns (uint256 amount) {
        uint256 numTokens = nftContract.balanceOf(msg.sender);
        uint256 rewards = 0;

        // Rewards of tokens owned by the sender
        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = nftContract.tokenOfOwnerByIndex(msg.sender, i);
            if (tokenId < TOTAL_NFTS_COUNT) {
                rewards +=
                    totalGivenRewardsPerToken -
                    communityRewards[tokenId];
            }
        }

        // Rewards of tokens owned by the sender, but listed on this marketplace
        uint256[] memory myListings = userActiveListings[msg.sender];
        for (uint256 i = 0; i < myListings.length; i++) {
            uint256 tokenId = listings[myListings[i]].tokenId;
            if (tokenId < TOTAL_NFTS_COUNT) {
                rewards +=
                    totalGivenRewardsPerToken -
                    communityRewards[tokenId];
            }
        }

        return rewards;
    }

    function claimListedRewards(uint256 from, uint256 length) external {
        require(
            from + length <= userActiveListings[msg.sender].length,
            "Out of index"
        );

        uint256 rewards = 0;
        uint256 newCommunityHoldings = communityHoldings;

        // Rewards of tokens owned by the sender, but listed on this marketplace
        uint256[] memory myListings = userActiveListings[msg.sender];
        for (uint256 i = 0; i < myListings.length; i++) {
            uint256 tokenId = listings[myListings[i]].tokenId;
            if (tokenId < TOTAL_NFTS_COUNT) {
                uint256 tokenReward = totalGivenRewardsPerToken -
                    communityRewards[tokenId];
                rewards += tokenReward;
                newCommunityHoldings -= tokenReward;
                communityRewards[tokenId] = totalGivenRewardsPerToken;
            }
        }

        communityHoldings = newCommunityHoldings;
        payable(msg.sender).transfer(rewards);
    }

    function claimOwnedRewards(uint256 from, uint256 length) external {
        uint256 numTokens = nftContract.balanceOf(msg.sender);
        require(from + length <= numTokens, "Out of index");

        uint256 rewards = 0;
        uint256 newCommunityHoldings = communityHoldings;

        // Rewards of tokens owned by the sender
        for (uint256 i = 0; i < length; i++) {
            uint256 tokenId = nftContract.tokenOfOwnerByIndex(
                msg.sender,
                i + from
            );
            if (tokenId < TOTAL_NFTS_COUNT) {
                uint256 tokenReward = totalGivenRewardsPerToken -
                    communityRewards[tokenId];
                rewards += tokenReward;
                newCommunityHoldings -= tokenReward;
                communityRewards[tokenId] = totalGivenRewardsPerToken;
            }
        }

        communityHoldings = newCommunityHoldings;
        payable(msg.sender).transfer(rewards);
    }

    function claimRewards() external {
        uint256 numTokens = nftContract.balanceOf(msg.sender);
        uint256 rewards = 0;
        uint256 newCommunityHoldings = communityHoldings;

        // Rewards of tokens owned by the sender
        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = nftContract.tokenOfOwnerByIndex(msg.sender, i);
            if (tokenId < TOTAL_NFTS_COUNT) {
                uint256 tokenReward = totalGivenRewardsPerToken -
                    communityRewards[tokenId];
                rewards += tokenReward;
                newCommunityHoldings -= tokenReward;
                communityRewards[tokenId] = totalGivenRewardsPerToken;
            }
        }

        // Rewards of tokens owned by the sender, but listed on this marketplace
        uint256[] memory myListings = userActiveListings[msg.sender];
        for (uint256 i = 0; i < myListings.length; i++) {
            uint256 tokenId = listings[myListings[i]].tokenId;
            if (tokenId < TOTAL_NFTS_COUNT) {
                uint256 tokenReward = totalGivenRewardsPerToken -
                    communityRewards[tokenId];
                rewards += tokenReward;
                newCommunityHoldings -= tokenReward;
                communityRewards[tokenId] = totalGivenRewardsPerToken;
            }
        }

        communityHoldings = newCommunityHoldings;

        payable(msg.sender).transfer(rewards);
    }

    function adjustFees(uint256 newDistFee, uint256 newMarketFee)
        external
        onlyOwner
    {
        require(newDistFee <= 100, "Give a percentage value from 0 to 100");
        require(newMarketFee <= 100, "Give a percentage value from 0 to 100");

        communityFeePercent = newDistFee;
        marketFeePercent = newMarketFee;
    }

    function emergencyDelist(uint256 listingID) external {
        require(emergencyDelisting && !isMarketOpen, "Only in emergency.");
        require(listingID < listings.length, "Invalid Listing");
        MrktStructs.Listing memory listing = listings[listingID];

        nftContract.transferFrom(address(this), listing.owner, listing.tokenId);
    }

    function withdrawableBalance() public view returns (uint256 value) {
        if (address(this).balance <= communityHoldings) {
            return 0;
        }
        return address(this).balance - communityHoldings;
    }

    function withdrawBalance() external onlyOwner {
        uint256 withdrawable = withdrawableBalance();
        payable(_msgSender()).transfer(withdrawable);
    }

    function emergencyWithdraw() external onlyOwner {
        payable(_msgSender()).transfer(address(this).balance);
    }
}
