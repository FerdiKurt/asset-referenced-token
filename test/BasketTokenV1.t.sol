// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/BasketTokenV1.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// Mock implementation of Chainlink price feed
contract MockPriceFeed is AggregatorV3Interface {
    int256 private _price;
    uint8 private _decimals;
    
    constructor(int256 initialPrice, uint8 decimals_) {
        _price = initialPrice;
        _decimals = decimals_;
    }
    
    function setPrice(int256 newPrice) external {
        _price = newPrice;
    }
    
    function decimals() external view returns (uint8) {
        return _decimals;
    }
    
    function description() external pure returns (string memory) {
        return "Mock Price Feed";
    }
    
    function version() external pure returns (uint256) {
        return 1;
    }
    
    function getRoundData(uint80 _roundId) external pure returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (_roundId, 0, 0, 0, 0);
    }
    
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (0, _price, block.timestamp, block.timestamp, 0);
    }
}

contract BasketTokenTest is Test {
    BasketToken public basketToken;
    
    MockPriceFeed public goldPriceFeed;
    MockPriceFeed public btcPriceFeed;
    MockPriceFeed public usdcPriceFeed;
    MockPriceFeed public ethUsdPriceFeed;
    
    // Test addresses
    address public owner = address(1);
    address public alice = address(2);
    address public bob = address(3);
    
    // Initial price values (8 decimals as per Chainlink standard)
    int256 public initialGoldPrice = 200000000000;  // $2,000 per oz
    int256 public initialBtcPrice = 7000000000000;  // $70,000 per BTC
    int256 public initialUsdcPrice = 100000000;     // $1.00 per USDC
    int256 public initialEthUsdPrice = 450000000000; // $4,500 per ETH
    
    uint256 public constant GOLD_PERCENTAGE = 4000;  // 40%
    uint256 public constant BTC_PERCENTAGE = 4000;   // 40%
    uint256 public constant USDC_PERCENTAGE = 2000;  // 20%
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant STANDARD_PRECISION = 1e18;
    uint256 public constant EXTENDED_PRECISION = 1e27;
    
    function setUp() public {
        // Create mock price feeds with initial values (8 decimals precision)
        goldPriceFeed = new MockPriceFeed(initialGoldPrice, 8);
        btcPriceFeed = new MockPriceFeed(initialBtcPrice, 8);
        usdcPriceFeed = new MockPriceFeed(initialUsdcPrice, 8);
        ethUsdPriceFeed = new MockPriceFeed(initialEthUsdPrice, 8);
        
        // Deploy contract as owner
        vm.startPrank(owner);
        
        basketToken = new BasketToken(
            "Basket Token",
            "BSKT",
            address(goldPriceFeed),
            address(btcPriceFeed),
            address(usdcPriceFeed),
            address(ethUsdPriceFeed)
        );
        
        vm.stopPrank();
        
        // Initialize users with ETH
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }
    // Test initial state
    function testInitialState() public view {
        assertEq(basketToken.name(), "Basket Token");
        assertEq(basketToken.symbol(), "BSKT");
        assertEq(basketToken.goldPercentage(), GOLD_PERCENTAGE);
        assertEq(basketToken.btcPercentage(), BTC_PERCENTAGE);
        assertEq(basketToken.usdcPercentage(), USDC_PERCENTAGE);
        assertEq(basketToken.totalSupply(), 0);
        assertEq(basketToken.totalBasketValueInUSD(), 0);
        assertEq(basketToken.owner(), owner);
    }
    
    // Test basket value calculation
    function testCalculateBasketValue() public view {
        // Calculated expected basket value
        // Gold: $2,000 * 40% = $800
        // BTC: $70,000 * 40% = $28,000
        // USDC: $1.00 * 20% = $0.20
        // Total: $28,800.20 or approximately $28,800
        
        uint256 expectedBasketValue = 28800 * 10**18; // Convert to 18 decimals
        uint256 calculatedBasketValue = basketToken.calculateBasketValueInUSD();
        
        // Allow for a small precision error due to calculations
        assertApproxEqRel(calculatedBasketValue, expectedBasketValue, 0.01e18); // 1% tolerance
    }
    
}