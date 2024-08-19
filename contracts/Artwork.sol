// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract ArtWorkManagement is ERC721 {
    address public owner;
    uint256 public totalArtWorks;
    uint256 public totalOrders;
    uint256 public totalBids;

    constructor(address _owner) ERC721("ArtWorkManagement", "AWM") {
        owner = _owner;
    }

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    struct ArtWork {
        uint256 id;
        string name;
        string description;
        uint256 price;
        string imageURI;
        address creator;
        address currentOwner;
        bool isVerified;
        bool isForSale;
        bool isPremium;
        uint256 bidDeadline;
        bid highestBid;
    }

    struct bid {
        uint256 id;
        uint256 artworkId;
        uint256 amount;
        address bidder;
    }

    struct Order {
        uint256 id;
        uint256 artworkId;
        uint256 amountPaid;
        uint256 amountRemaining;
        address buyer;
        DeliveryStatus status;
    }

    enum DeliveryStatus {
        InWarehouse,
        InTransit,
        Delivered
    }

    mapping(uint256 => ArtWork) public artworks;
    mapping(uint256 => mapping(uint256 => bid)) public bids;
    mapping(uint256 => Order) public orders;

    event ArtWorkCreated(
        uint256 id,
        string name,
        string description,
        uint256 price,
        string imageURI,
        address creator,
        address currentOwner,
        bool isVerified,
        bool isForSale,
        bool isPremium
    );
    event ArtWorkUpdated(
        uint256 id,
        string name,
        string description,
        uint256 price,
        string imageURI,
        address creator,
        address currentOwner,
        bool isVerified,
        bool isForSale,
        bool isPremium
    );

    event ArtWorkVerified(uint256 id);

    event ArtWorkForSale(uint256 id);
    event ArtWorkNotForSale(uint256 id);

    event ArtWorkOrdered(
        uint256 id,
        uint256 artworkId,
        uint256 amountPaid,
        uint256 amountRemaining,
        address buyer,
        DeliveryStatus status
    );
    event ArtWorkDelivered(uint256 id, DeliveryStatus status);

    event ArtWorkBid(uint256 id, uint256 price, address bidder);

    function createArtWork(
        string memory name,
        string memory description,
        uint256 price,
        string memory imageURI,
        bool isPremium
    ) public returns (uint256) {
        _tokenIds.increment();
        uint256 id = _tokenIds.current();

        ArtWork memory newArtWork = ArtWork(
            id,
            name,
            description,
            price,
            imageURI,
            msg.sender,
            msg.sender,
            false,
            false,
            isPremium,
            0,
            bid(0, 0, 0, address(0))
        );
        artworks[id] = newArtWork;

        emit ArtWorkCreated(
            id,
            name,
            description,
            price,
            imageURI,
            msg.sender,
            msg.sender,
            false,
            false,
            isPremium
        );

        _mint(msg.sender, id);
        return id;
    }

    function updateArtWork(
        uint256 id,
        string memory name,
        string memory description,
        uint256 price,
        string memory imageURI
    ) public {
        require(
            ownerOf(id) == msg.sender,
            "You are not the owner of this artwork"
        );
        ArtWork storage artwork = artworks[id];
        artwork.name = name;
        artwork.description = description;
        artwork.price = price;
        artwork.imageURI = imageURI;

        emit ArtWorkUpdated(
            id,
            name,
            description,
            price,
            imageURI,
            artwork.creator,
            artwork.currentOwner,
            artwork.isVerified,
            artwork.isForSale,
            artwork.isPremium
        );
    }

    function verifyArtWork(uint256 id) public {
        require(owner == msg.sender, "You are not the owner of this contract");
        ArtWork storage artwork = artworks[id];
        artwork.isVerified = true;

        emit ArtWorkVerified(id);
    }

    function setArtWorkForSale(uint256 id) public {
        require(
            ownerOf(id) == msg.sender,
            "You are not the owner of this artwork"
        );
        ArtWork storage artwork = artworks[id];
        artwork.isForSale = true;

        emit ArtWorkForSale(id);
    }

    function setArtWorkNotForSale(uint256 id) public {
        require(
            ownerOf(id) == msg.sender,
            "You are not the owner of this artwork"
        );
        ArtWork storage artwork = artworks[id];
        artwork.isForSale = false;

        emit ArtWorkNotForSale(id);
    }

    //write function for order artwork which initially takes 10% of the price as advance and the rest of the amount after the delivery of the artwork
    function orderArtWork(uint256 id) public payable {
        ArtWork storage artwork = artworks[id];
        require(artwork.isForSale == true, "Artwork is not for sale");
        require(
            msg.value == artwork.price / 10,
            "Please pay 10% of the price as advance"
        );

        totalOrders++;
        uint256 orderId = totalOrders;

        //make the payment
        payable(artwork.currentOwner).transfer(msg.value);

        Order memory newOrder = Order(
            orderId,
            id,
            msg.value,
            artwork.price - msg.value,
            msg.sender,
            DeliveryStatus.InWarehouse
        );
        orders[orderId] = newOrder;

        emit ArtWorkOrdered(
            orderId,
            id,
            msg.value,
            artwork.price - msg.value,
            msg.sender,
            DeliveryStatus.InWarehouse
        );
    }

    function updateDeliveryStatus(uint256 orderId) public payable {
        Order storage order = orders[orderId];

        // Ensure that the caller is either the current owner or the contract owner
        require(
            msg.sender == artworks[order.artworkId].currentOwner ||
                msg.sender == owner,
            "You are not authorized to update this order"
        );

        // Update the delivery status
        if (order.status == DeliveryStatus.InWarehouse) {
            order.status = DeliveryStatus.InTransit;
        } else if (order.status == DeliveryStatus.InTransit) {
            //require the remaining amound is paid
            require(
                msg.value == order.amountRemaining,
                "Please pay the remaining amount to update the delivery status"
            );

            order.status = DeliveryStatus.Delivered;

            // Transfer the remaining amount to the current owner
            payable(artworks[order.artworkId].currentOwner).transfer(msg.value);

            // Transfer the ownership of the artwork to the buyer
            _transfer(
                artworks[order.artworkId].currentOwner,
                order.buyer,
                order.artworkId
            );

            // Emit the event
            emit ArtWorkDelivered(orderId, DeliveryStatus.Delivered);
        } else {
            revert("Order is already delivered or in an invalid state");
        }
    }

    function startBid(uint256 id, uint256 bidDeadline) public {
        ArtWork storage artwork = artworks[id];
        require(artwork.isPremium == true, "Artwork is not premium");
        require(
            ownerOf(id) == msg.sender,
            "You are not the owner of this artwork"
        );

        artwork.isForSale = true;
        artwork.bidDeadline = bidDeadline;
    }

    function bidForArtWork(uint256 id, uint256 amount) public {
        ArtWork storage artwork = artworks[id];
        require(artwork.isForSale == true, "Artwork is not for sale");
        require(artwork.bidDeadline > block.timestamp, "Bid deadline is over");
        require(artwork.isPremium == true, "Artwork is not premium");
        require(
            amount > artwork.highestBid.amount && amount > artwork.price,
            "Please bid higher than the highest bid and the price"
        );
        require(
            msg.sender != artwork.currentOwner,
            "You are the owner of this artwork"
        );

        totalBids++;
        uint256 bidId = totalBids;

        bid memory newBid = bid(bidId, id, amount, msg.sender);
        bids[id][bidId] = newBid;

        emit ArtWorkBid(bidId, amount, msg.sender);
    }

    function acceptBid(uint256 id) public payable {
        ArtWork storage artwork = artworks[id];
        require(
            ownerOf(id) == msg.sender,
            "You are not the owner of this artwork"
        );
        require(artwork.isPremium == true, "Artwork is not premium");
        require(artwork.bidDeadline < block.timestamp, "Bid deadline is not over");
        require(artwork.highestBid.amount > 0, "No bids for this artwork");

        bid storage acceptedBid = artwork.highestBid;
        
        // Transfer the ownership of the artwork to the buyer
        _transfer(artwork.currentOwner, acceptedBid.bidder, id);

        // Transfer the amount to the current owner
        payable(artwork.currentOwner).transfer(acceptedBid.amount);

        // Update the current owner
        artwork.currentOwner = acceptedBid.bidder;

        emit ArtWorkDelivered(acceptedBid.id, DeliveryStatus.Delivered);

        artwork.highestBid = bid(0, 0, 0, address(0));
        artwork.isForSale = false;
        artwork.bidDeadline = 0;
        emit ArtWorkNotForSale(id);


    }

    function getArtWork(uint256 id)
        public
        view
        returns (
            uint256,
            string memory,
            string memory,
            uint256,
            string memory,
            address,
            address,
            bool,
            bool,
            bool,
            uint256,
            bid memory
        )
    {
        ArtWork memory artwork = artworks[id];
        return (
            artwork.id,
            artwork.name,
            artwork.description,
            artwork.price,
            artwork.imageURI,
            artwork.creator,
            artwork.currentOwner,
            artwork.isVerified,
            artwork.isForSale,
            artwork.isPremium,
            artwork.bidDeadline,
            artwork.highestBid
        );
    }

    function getOrder(uint256 id)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            address,
            DeliveryStatus
        )
    {
        Order memory order = orders[id];
        return (
            order.id,
            order.artworkId,
            order.amountPaid,
            order.amountRemaining,
            order.buyer,
            order.status
        );
    }

    function getBid(uint256 artworkId, uint256 bidId)
        public
        view
        returns (bid memory)
    {
        return bids[artworkId][bidId];
    }

    function getMyArtWorks() public view returns (uint256[] memory) {
        uint256[] memory myArtWorks = new uint256[](balanceOf(msg.sender));
        uint256 counter = 0;
        for (uint256 i = 0; i < totalArtWorks; i++) {
            if (ownerOf(i) == msg.sender) {
                myArtWorks[counter] = i;
                counter++;
            }
        }
        return myArtWorks;
    }

    function getMyOrders() public view returns (uint256[] memory) {
        uint256[] memory myOrders = new uint256[](totalOrders);
        uint256 counter = 0;
        for (uint256 i = 0; i < totalOrders; i++) {
            if (orders[i].buyer == msg.sender) {
                myOrders[counter] = i;
                counter++;
            }
        }
        return myOrders;
    }

    function getMyBids() public view returns (uint256[] memory) {
        uint256[] memory myBids = new uint256[](totalBids);
        uint256 counter = 0;
        for (uint256 i = 0; i < totalBids; i++) {
            if (bids[i][i].bidder == msg.sender) {
                myBids[counter] = i;
                counter++;
            }
        }
        return myBids;
    }

    //get all artworks for sell not owned by me
    function getArtWorksForSale() public view returns (uint256[] memory) {
        uint256[] memory artWorksForSale = new uint256[](totalArtWorks);
        uint256 counter = 0;
        for (uint256 i = 0; i < totalArtWorks; i++) {
            if (
                ownerOf(i) != msg.sender &&
                artworks[i].isForSale == true
            ) {
                artWorksForSale[counter] = i;
                counter++;
            }
        }
        uint256[] memory result = new uint256[](counter);
        for (uint256 i = 0; i < counter; i++) {
            result[i] = artWorksForSale[i];
        }
        return result;
    }

    //get premium artworks for bid
    function getPremiumArtWorksForBid() public view returns (uint256[] memory) {
        uint256[] memory premiumArtWorksForBid = new uint256[](totalArtWorks);
        uint256 counter = 0;
        for (uint256 i = 0; i < totalArtWorks; i++) {
            if (
                ownerOf(i) != msg.sender &&
                artworks[i].isForSale == true &&
                artworks[i].isPremium == true
            ) {
                premiumArtWorksForBid[counter] = i;
                counter++;
            }
        }
        uint256[] memory result = new uint256[](counter);
        for (uint256 i = 0; i < counter; i++) {
            result[i] = premiumArtWorksForBid[i];
        }
        return result;
    }

    //get all bids for a premium artwork
    function getBidsForArtWork(uint256 id)
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory bidsForArtWork = new uint256[](totalBids);
        uint256 counter = 0;
        for (uint256 i = 0; i < totalBids; i++) {
            if (bids[id][i].artworkId == id) {
                bidsForArtWork[counter] = i;
                counter++;
            }
        }
        uint256[] memory result = new uint256[](counter);
        for (uint256 i = 0; i < counter; i++) {
            result[i] = bidsForArtWork[i];
        }
        return result;
    }
}
