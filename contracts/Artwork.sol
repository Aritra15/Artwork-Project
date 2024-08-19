// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract ArtWorkManagement is ERC721 {
    address public owner;
    uint256 public totalArtWorks;
    uint256 public totalOrders;

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
    }

    struct bid {
        uint256 id;
        uint256 artworkId;
        uint256 price;
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
            0
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
            require( msg.value == order.amountRemaining, "Please pay the remaining amount to update the delivery status");
            
            order.status = DeliveryStatus.Delivered;

            // Transfer the remaining amount to the current owner
            payable(artworks[order.artworkId].currentOwner).transfer(
                msg.value
            );

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
}
