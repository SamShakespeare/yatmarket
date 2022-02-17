// SPDX-License-Identifier: Unlicense

library List{
    struct Bid {
        uint id;
        uint bidPrice;
        address bidder;
    }

    function createBid (Bid[] storage _bids) public {
        uint bidId = _bids.length;

        _bids[bidId].push(Bid(bidId, msg.value, msg.sender));
    }
}

contract TestContract {
    using List for List.Bid[];
    mapping(uint256 => List.Bid[]) public bids;

    function placeBid(uint256 listingId) external payable {
        //uint256 bidId = bids[listingId].length;
        List.createBid(bids[listingId]);
    }

   
}
