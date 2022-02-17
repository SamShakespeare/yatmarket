// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "ds-test/test.sol";
import "../YATMarket.sol";
import "./ERC721Mock.sol";
import "./console.sol";

interface HEVM {
    function warp(uint256 time) external;
    function prank(address sender) external;
    function startPrank(address) external;
    function stopPrank() external;
    function expectEmit(bool,bool,bool,bool) external;
    function deal(address who, uint256 newBalance) external;
}

contract YATMarketTest is DSTest {
    HEVM private hevm = HEVM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    YATMarket private yatmkt;
    ERC721Mock private mockToken;
    address owner;

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

    function setUp() public {
        owner = address(this);
        mockToken = new ERC721Mock("Mock", "MOCK");
        //console.log("addy: ",address(mockToken));
        //console.log("addy1: ",address(1));
        yatmkt = new YATMarket(address(mockToken),1);
        yatmkt.openMarket();

        hevm.deal(address(yatmkt), 10 ether);
        hevm.deal(address(1), 10 ether);
        hevm.deal(address(2), 10 ether);
        hevm.deal(address(3), 10 ether);
       
        assert(address(1).balance == 10 ether);  
        assert(address(2).balance == 10 ether);
        assert(address(3).balance == 10 ether);
        assert(address(yatmkt).balance == 10 ether);  
        
        hevm.startPrank(address(6));
        //mint some nfts
        for(uint i = 0; i<=30; i++){
            mockToken.mint(i);
        }
        mockToken.setApprovalForAll(address(yatmkt), true);

        yatmkt.addListing(1,2 ether);
        yatmkt.addListing(2,3 ether);
        yatmkt.addListing(3,4 ether);
        yatmkt.addListing(4,5 ether);
        hevm.stopPrank();
    }

    function testExample() public {
        assertTrue(true);
    }

    function testListings() public {
        (,,uint tknId,uint price,,,address lister,) = yatmkt.listings(1);
        console.log("tknId: ",tknId);
        console.log("price: ",price);
        console.log("lister: ",lister);
    }

    //for yatMarketMain
    function testPlaceBid() public {
        uint256 testToken = 10;
        console.log("market balance before bids: ",address(yatmkt).balance);

        uint256 nextBid = 3 ether;
        uint256 x = 2;
        uint256 cnt;
        for(uint256 i = 0; i<x; i++){

            hevm.prank(address(1));
            yatmkt.placeBid{value: nextBid}(testToken);
            (uint256 bId,uint256 tokenId, uint256 bprice, address bidder, YATMarket.Status _status) = yatmkt.bids(testToken,cnt);
            nextBid -= .1 ether;
            cnt++;

            hevm.prank(address(2));
            yatmkt.placeBid{value: nextBid}(testToken);
            ( bId, tokenId, bprice,  bidder, _status) = yatmkt.bids(testToken,cnt);
            nextBid -= .1 ether;
            cnt++;

            hevm.prank(address(3));
            yatmkt.placeBid{value: nextBid}(testToken);
            ( bId, tokenId, bprice,  bidder, _status) = yatmkt.bids(testToken,cnt);
            console.log("bId: ",bId);
            console.log("bidder: ",bidder);
            console.log("bPrice: ",bprice);
            console.log("tokenId: ",tokenId);
            console.log("Status: ",uint256(_status));
            nextBid += 1.5 ether;
            cnt++;
        } 

        //now lets accept one of the bids
        console.log("token owner ether balance before bid accepted: ",address(6).balance);
        console.log("buyer token balance before bid accepted: ",mockToken.balanceOf(address(1)));
        hevm.prank(address(6));
        yatmkt.acceptBid(testToken, 3);
        console.log("token owner ether balance after bid accepted: ",address(6).balance);
        console.log("buyer token balance after bid accepted: ",mockToken.balanceOf(address(1)));

        //buyer cancels his remaining bid
        console.log("new token owner ether balance before bid cancelled: ",address(1).balance);
        hevm.prank(address(1));
        yatmkt.cancelBid(testToken, 0);
        console.log("token owner ether balance after bid cancelled: ",address(1).balance);
        
        //now let new owner accept one of the previous bids
        console.log("new token owner ether balance before bid accepted: ",address(1).balance);
        console.log("new buyer token balance before bid accepted: ",mockToken.balanceOf(address(2)));
        hevm.startPrank(address(1));
        mockToken.setApprovalForAll(address(yatmkt), true);
        yatmkt.acceptBid(testToken, 4);
        hevm.stopPrank();
        console.log("new token owner ether balance after bid accepted: ",address(1).balance);
        console.log("new buyer token balance after bid accepted: ",mockToken.balanceOf(address(2)));

    }

    function testFulfillListing() public {
       // uint256 _bid = 1 ether;
        hevm.deal(address(4), 15 ether);
        assert(address(4).balance == 15 ether); 
       
        uint256[] memory listingIDS = new uint256[](4);
        listingIDS[0] = 1;
        listingIDS[1] = 2;
        listingIDS[2] = 3;
        listingIDS[3] = 4;
        hevm.prank(address(4));
        yatmkt.fulfillListing{value: 14 ether}(listingIDS);    
    }

    function testUpdateListing() public {
        hevm.prank(address(6));
        yatmkt.updateListing(1,5 ether);
        (,,,uint updatedListing,,,,) = yatmkt.listings(1);
        assertEq(5 ether,updatedListing);
    }

    function testCancelListing() public {
        //check balance of listing.owner
        console.log("listing.owner token balance before listing cancelled: ",mockToken.balanceOf(address(6)));
        (bool active,,,,,,,) = yatmkt.listings(1);
        assertTrue(active);
        hevm.prank(address(6));
        yatmkt.cancelListing(1);
        //recheck balance of listing.owner
        console.log("listing.owner token balance after listing cancelled: ",mockToken.balanceOf(address(6)));
        (active,,,,,,,) = yatmkt.listings(1);
        assertTrue(!active);
    }

    function testGetTokenOwner() public{
        uint256 tokenId = 5;
        address tokenOwner = yatmkt.getTokenOwner(tokenId);
        //owner lists token
        hevm.prank(tokenOwner);
        yatmkt.addListing(tokenId, 10000000000000000000);
        //check to see if getTokenOwner function returns lister as owner 
        assertEq(tokenOwner,yatmkt.getTokenOwner(tokenId));
        //check to see if market is actually holding token 
        assertEq(address(yatmkt), mockToken.ownerOf(tokenId));
    }
   
}
