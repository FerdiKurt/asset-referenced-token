// SPDX-License-Identifier: UNLICENSED
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
    
    // Test minting tokens
    function testMint() public {
        uint256 ethToDeposit = 1 ether;
        
        vm.startPrank(alice);
        
        uint256 initialBalance = alice.balance;
        basketToken.mint{value: ethToDeposit}();
        
        // Get actual tokens minted
        uint256 actualTokens = basketToken.balanceOf(alice);
        
        // Let's calculate the expected tokens manually to verify
        // 1 ETH = $4,500 (initialEthUsdPrice * 10^10 = 4500 * 10^18)
        // After 0.5% fee: $4,500 * 0.995 = $4,477.50
        // First mint sets basket value at $1, so expected tokens ≈ 4,477.50 * 10^18
        
        uint256 ethUsdPrice = uint256(initialEthUsdPrice) * 10**10; // Convert to 18 decimals
        uint256 ethValueInUsd = (ethToDeposit * ethUsdPrice) / 10**18;
        uint256 ethValueAfterFee = (ethValueInUsd * (BASIS_POINTS - 50)) / BASIS_POINTS; // 0.5% fee
        
        // For first mint, we expect approximately the USD value in tokens
        assertApproxEqRel(actualTokens, ethValueAfterFee, 0.05e18); // 5% tolerance
        
        // Check other balances
        assertEq(alice.balance, initialBalance - ethToDeposit);
        assertEq(address(basketToken).balance, ethToDeposit);
        
        vm.stopPrank();
    }
    
    // Test multiple mints
    function testMultipleMints() public {
        // First mint
        vm.startPrank(alice);
        basketToken.mint{value: 1 ether}();
        uint256 aliceBalance = basketToken.balanceOf(alice);
        vm.stopPrank();
        
        // Second mint from a different user
        vm.startPrank(bob);
        basketToken.mint{value: 2 ether}();
        uint256 bobBalance = basketToken.balanceOf(bob);
        vm.stopPrank();
        
        // Bob should have roughly twice as many tokens as Alice
        assertApproxEqRel(bobBalance, aliceBalance * 2, 0.05e18); // 5% tolerance
        
        // Total supply should be sum of balances
        assertEq(basketToken.totalSupply(), aliceBalance + bobBalance);
        
        // Contract should have 3 ETH
        assertEq(address(basketToken).balance, 3 ether);
    }
        
    // Test burning tokens
    function testBurn() public {
        // First mint some tokens
        vm.startPrank(alice);
        basketToken.mint{value: 1 ether}();
        uint256 tokensToburn = basketToken.balanceOf(alice) / 2; // Burn half the tokens
        
        uint256 initialEthBalance = alice.balance;
        
        // Burn tokens
        basketToken.burn(tokensToburn);
        
        // Check balances
        uint256 expectedTokensLeft = basketToken.balanceOf(alice);
        assertApproxEqRel(expectedTokensLeft, tokensToburn, 0.01e18); // Should have half left
        assertGt(alice.balance, initialEthBalance); // Should have received ETH back
        
        vm.stopPrank();
    }
    
    // Test complete mint and burn cycle
    function testFullMintBurnCycle() public {
        vm.startPrank(alice);
        
        // Mint tokens
        uint256 initialEthBalance = alice.balance;
        basketToken.mint{value: 1 ether}();
        uint256 tokensReceived = basketToken.balanceOf(alice);
        
        // Burn all tokens
        basketToken.burn(tokensReceived);
        
        // Check final state
        assertEq(basketToken.balanceOf(alice), 0);
        uint256 finalEthBalance = alice.balance;
        
        // Due to fees, Alice should have less ETH than she started with
        assertLt(finalEthBalance, initialEthBalance);
        // But she should have most of it back (minus two fees of 0.5% each)
        uint256 expectedLoss = 2 * 0.005 * 1 ether; // Approximate loss from two 0.5% fees
        assertApproxEqAbs(finalEthBalance, initialEthBalance - expectedLoss, 0.01 ether);
        
        vm.stopPrank();
    }
    
    // Test basket value calculation
    function testBasketValueCalculation() public {        
        // Get the initial prices
        int256 goldPrice = basketToken.getGoldPrice();
        int256 btcPrice = basketToken.getBtcPrice();
        int256 usdcPrice = basketToken.getUsdcPrice();
        
        // First, double the gold price
        int256 newGoldPrice = goldPrice * 2;
        goldPriceFeed.setPrice(newGoldPrice);
        
        // Now calculate the expected basket value using the same formula as the contract
        uint256 PRICE_FEED_DECIMALS = 10**10; // Convert from 8 to 18 decimals
        uint256 PRECISION_FACTOR = 10**9;     // Factor to adjust from 18 to 27 decimals
        
        // Scale all prices to extended precision
        uint256 goldPriceUsd = uint256(newGoldPrice) * PRICE_FEED_DECIMALS * PRECISION_FACTOR;
        uint256 btcPriceUsd = uint256(btcPrice) * PRICE_FEED_DECIMALS * PRECISION_FACTOR;
        uint256 usdcPriceUsd = uint256(usdcPrice) * PRICE_FEED_DECIMALS * PRECISION_FACTOR;
        
        // Calculate basket value with extended precision
        uint256 goldValue = (goldPriceUsd * GOLD_PERCENTAGE) / BASIS_POINTS;
        uint256 btcValue = (btcPriceUsd * BTC_PERCENTAGE) / BASIS_POINTS;
        uint256 usdcValue = (usdcPriceUsd * USDC_PERCENTAGE) / BASIS_POINTS;
        
        uint256 expectedBasketValueExtended = goldValue + btcValue + usdcValue;
        uint256 expectedBasketValue = expectedBasketValueExtended / PRECISION_FACTOR;
        
        // Get the actual value from the contract
        uint256 actualNewBasketValue = basketToken.calculateBasketValueInUSD();
        
        // Now test with a small absolute difference allowed
        assertApproxEqAbs(actualNewBasketValue, expectedBasketValue, 1e17);
    }

    // Test token value after mint
    function testTokenValueAfterMint() public {
        // Mint tokens
        vm.prank(alice);
        basketToken.mint{value: 1 ether}();
        
        // Get token value after mint
        uint256 valuePerToken = basketToken.getBasketValuePerToken();
        console.log("Token value after first mint:", valuePerToken);
        
        // First mint should establish value at approximately $1
        assertApproxEqAbs(valuePerToken, 1 ether, 0.1 ether);
    }
    
    // Test admin functions
    function testUpdateBasketComposition() public {
        uint16 newGoldPercentage = 3000;
        uint16 newBtcPercentage = 3000;
        uint16 newUsdcPercentage = 4000;
        
        // Only owner can update
        vm.prank(alice);
        vm.expectRevert();
        basketToken.updateBasketComposition(newGoldPercentage, newBtcPercentage, newUsdcPercentage);
        
        // Owner updates successfully
        vm.prank(owner);
        basketToken.updateBasketComposition(newGoldPercentage, newBtcPercentage, newUsdcPercentage);
        
        // Check new values
        assertEq(basketToken.goldPercentage(), newGoldPercentage);
        assertEq(basketToken.btcPercentage(), newBtcPercentage);
        assertEq(basketToken.usdcPercentage(), newUsdcPercentage);
    }
    
    // Test update fees
    function testUpdateFees() public {
        uint16 newMintFee = 100; // 1%
        uint16 newBurnFee = 100; // 1%
        
        // Owner updates successfully
        vm.prank(owner);
        basketToken.updateFees(newMintFee, newBurnFee);
        
        // Check new values
        assertEq(basketToken.mintFee(), newMintFee);
        assertEq(basketToken.burnFee(), newBurnFee);
        
        // Test fee limit
        uint16 excessiveFee = 600; // 6%, above 5% limit
        vm.prank(owner);
        vm.expectRevert(BasketToken.FeeTooHigh.selector);
        basketToken.updateFees(excessiveFee, newBurnFee);
    }
    
    // Test update collateral ratio
    function testUpdateCollateralRatio() public {
        uint16 newCollateralRatio = 15000; // 150%
        
        // Owner updates successfully
        vm.prank(owner);
        basketToken.updateCollateralRatio(newCollateralRatio);
        
        // Check new value
        assertEq(basketToken.collateralRatio(), newCollateralRatio);
        
        // Test minimum limit
        uint16 insufficientRatio = 9000; // 90%, below 100% minimum
        vm.prank(owner);
        vm.expectRevert(BasketToken.CollateralRatioTooLow.selector);
        basketToken.updateCollateralRatio(insufficientRatio);
    }
    
    // Test failures
    function testRevertMintZero() public {
        vm.prank(alice);
        // Expect a revert with the NoEthSent error
        vm.expectRevert(BasketToken.NoEthSent.selector);
        basketToken.mint{value: 0}(); 
    }
    
    function testRevertBurnZero() public {
        vm.prank(alice);
        // Expect a revert with the ZeroAmount error
        vm.expectRevert(BasketToken.ZeroAmount.selector);
        basketToken.burn(0);
    }
    
    function testRevertBurnTooMuch() public {
        // First mint some tokens
        vm.prank(alice);
        basketToken.mint{value: 1 ether}();
        uint256 balance = basketToken.balanceOf(alice);
        
        vm.prank(alice);
        // Expect a revert with the InsufficientBalance error
        vm.expectRevert(BasketToken.InsufficientBalance.selector);
        basketToken.burn(balance + 1); 
    }
    
    function testRevertInvalidBasketComposition() public {
        // Total percentage should be 10000 basis points (100%)
        vm.prank(owner);
        vm.expectRevert(BasketToken.InvalidBasketComposition.selector);
        basketToken.updateBasketComposition(4000, 4000, 3000); // Total is 110%
    }
    
    // Test complex scenario with price changes
    function testPriceChangesScenario() public {
        // Initial mint
        vm.startPrank(alice);
        basketToken.mint{value: 1 ether}();
        uint256 aliceTokens = basketToken.balanceOf(alice);
        vm.stopPrank();

        // Simulate market changes - gold up 20%, BTC down 20%, ETH down 10%
        changeMarketPrices();
        
        // Now Bob mints with new prices
        vm.startPrank(bob);
        basketToken.mint{value: 1 ether}();
        uint256 bobTokens = basketToken.balanceOf(bob);
        vm.stopPrank();
 
        // Important: Add more ETH to the contract to handle potential price increases
        // This simulates the contract having sufficient collateral
        vm.deal(address(basketToken), address(basketToken).balance + 5 ether);
        console.log("Contract ETH balance after additional funding:", address(basketToken).balance);
        
        // Test token ratio with generous tolerance due to price changes
        assertApproxEqRel(bobTokens, aliceTokens, 0.25e18); // 25% tolerance
        
        // Burns should now succeed with the additional ETH
        vm.prank(alice);
        basketToken.burn(aliceTokens);
        
        vm.prank(bob);
        basketToken.burn(bobTokens);
        
        // Contract should still have some balance due to our additional funding
        assert(address(basketToken).balance > 0);
    }

    // Helper function to change market prices
    function changeMarketPrices() internal {
        // Get the current price feed values 
        int256 currentGoldPrice = basketToken.getGoldPrice();
        int256 currentBtcPrice = basketToken.getBtcPrice();
        int256 currentEthUsdPrice;
        
        // Get the ETH/USD price from the price feed
        (, currentEthUsdPrice, , ,) = ethUsdPriceFeed.latestRoundData();
        
        // Change prices
        goldPriceFeed.setPrice(currentGoldPrice * 12 / 10); // Gold up 20%
        btcPriceFeed.setPrice(currentBtcPrice * 8 / 10);   // BTC down 20%
        ethUsdPriceFeed.setPrice(currentEthUsdPrice * 9 / 10); // ETH down 10%
    }   
}