

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PriceFeed2 is Ownable {
   AggregatorV3Interface public wstETHfeed = AggregatorV3Interface(0xb523AE262D20A936BC152e6023996e46FDC2A95D);
   AggregatorV3Interface public rETHfeed = AggregatorV3Interface(0xF3272CAfe65b190e76caAF483db13424a3e23dD2);

   uint256 public SfrxETHPrice;
   address public bridge;
   uint256 public lastUpdate = block.timestamp;

   mapping(uint =>  function () view returns (uint256)) funcMap;

   constructor() {
        funcMap[0] = getRETHprice;
        funcMap[1] =  getWstETHprice;
        funcMap[2] =  getSfrxETHprice;
   }

   function getLatestPrice(AggregatorV3Interface feed) public view returns (int) {
    (
        uint80 roundID, 
        int price,
        uint startedAt,
        uint timeStamp,
        uint80 answeredInRound
    ) = feed.latestRoundData();
    return price;
    }

    function getRETHprice() public view returns (uint256) {
        return uint256(getLatestPrice(rETHfeed));
    }

    function getWstETHprice() public view returns (uint256) {
        return uint256(getLatestPrice(wstETHfeed));
    }

    function updateBridge(address _bridge) external onlyOwner  {
        bridge = _bridge;

    }

    
    function getSfrxETHprice() public view returns (uint256) {
        return SfrxETHPrice;
    }

    function setSfrxETHprice(uint256 price) public returns (uint256) {
        require(msg.sender == bridge, "not bridge");
        if (SfrxETHPrice > 1e18) {
            require((price - SfrxETHPrice) <= 1e16, "increase too much");
            require((block.timestamp - lastUpdate) >= 5 minutes, "update too soon");
            lastUpdate = block.timestamp;
        }
        SfrxETHPrice = price;
        return SfrxETHPrice;
    }

    function getPrice(uint id) public view returns (uint256) {
        return funcMap[id]();
    }
}
