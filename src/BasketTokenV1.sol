// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title BasketToken
 * @dev A token pegged to a basket of assets including gold, BTC, and USDC with enhanced precision
 */
contract BasketToken is ERC20, Ownable {
    // Custom errors
    error InvalidBasketComposition();
    error ZeroAmount();
    error InsufficientBalance();
    error InsufficientContractBalance();
    error EthTransferFailed();
    error FeeTooHigh();
    error CollateralRatioTooLow();
    error NoEthSent();
    error PrecisionLoss();

    // Price feed interfaces
    AggregatorV3Interface public immutable goldPriceFeed;
    AggregatorV3Interface public immutable btcPriceFeed;
    AggregatorV3Interface public immutable usdcPriceFeed;
    
    // Basket composition (in basis points, total should be 10000)
    uint16 public goldPercentage = 4000; // 40%
    uint16 public btcPercentage = 4000;  // 40%
    uint16 public usdcPercentage = 2000; // 20%
    
    // USD price feed for conversion
    AggregatorV3Interface public immutable ethusdPriceFeed;
    
    // Minimum collateralization ratio (in basis points, 10000 = 100%)
    uint16 public collateralRatio = 12000; // 120%
    
    // Fees (in basis points, 100 = 1%)
    uint16 public mintFee = 50;  // 0.5%
    uint16 public burnFee = 50;  // 0.5%
    
    // Total value of assets in USD (scaled by EXTENDED_PRECISION)
    uint256 public totalBasketValueInUSD;

    // Constants
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant PRICE_FEED_DECIMALS = 1e10; // Convert from 8 to 18 decimals
    uint256 private constant STANDARD_PRECISION = 1e18;  // Standard ERC20 decimals
    uint256 private constant EXTENDED_PRECISION = 1e27;  // Extended precision for calculations
    uint256 private constant PRECISION_FACTOR = 1e9;     // Factor to adjust from 18 to 27 decimals
    
    // Events
    event Minted(address indexed user, uint256 tokenAmount, uint256 ethAmount);
    event Burned(address indexed user, uint256 tokenAmount, uint256 ethAmount);
    event BasketUpdated(uint16 goldPercentage, uint16 btcPercentage, uint16 usdcPercentage);
    event OracleUpdated(address goldOracle, address btcOracle, address usdcOracle, address ethUsdOracle);
    event FeesUpdated(uint16 mintFee, uint16 burnFee);
    event CollateralRatioUpdated(uint16 collateralRatio);
    
    /**
    * @dev Constructor
    * @param _name Token name
    * @param _symbol Token symbol
    * @param _goldPriceFeed Address of gold price feed
    * @param _btcPriceFeed Address of BTC price feed
    * @param _usdcPriceFeed Address of USDC price feed
    * @param _ethusdPriceFeed Address of ETH/USD price feed
    */
    constructor(
        string memory _name,
        string memory _symbol,
        address _goldPriceFeed,
        address _btcPriceFeed,
        address _usdcPriceFeed,
        address _ethusdPriceFeed
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        goldPriceFeed = AggregatorV3Interface(_goldPriceFeed);
        btcPriceFeed = AggregatorV3Interface(_btcPriceFeed);
        usdcPriceFeed = AggregatorV3Interface(_usdcPriceFeed);
        ethusdPriceFeed = AggregatorV3Interface(_ethusdPriceFeed);
        
        if (goldPercentage + btcPercentage + usdcPercentage != BASIS_POINTS) {
            revert InvalidBasketComposition();
        }
    }
        
    /**
    * @dev Receive function to accept ETH
    */
    receive() external payable {}
    
    /**
    * @dev Mint new tokens by providing ETH collateral
    */
    function mint() external payable {
        if (msg.value == 0) revert NoEthSent();
        
        // Calculate how many tokens to mint based on the current basket value
        uint256 ethUsdPrice = getEthUsdPrice();
        
        // Use extended precision for calculations
        uint256 ethValueInUsd = (msg.value * ethUsdPrice * PRECISION_FACTOR) / STANDARD_PRECISION;
        
        // Apply mint fee
        uint256 ethValueAfterFee = (ethValueInUsd * (BASIS_POINTS - mintFee)) / BASIS_POINTS;
        
        // Calculate token amount based on basket value per token
        uint256 basketValuePerToken = getExtendedBasketValuePerToken();
        
        // Initial value $1 if this is the first mint
        if (basketValuePerToken == 0) basketValuePerToken = EXTENDED_PRECISION;
        
        // Calculate tokens to mint
        uint256 tokensToMint = (ethValueAfterFee * STANDARD_PRECISION) / basketValuePerToken;
        
        // Ensure we don't lose precision
        if ((tokensToMint * basketValuePerToken) / STANDARD_PRECISION < ethValueAfterFee * 99 / 100) {
            revert PrecisionLoss();
        }
        
        // Update total basket value
        totalBasketValueInUSD = totalBasketValueInUSD + ethValueAfterFee;
        
        // Mint tokens
        _mint(msg.sender, tokensToMint);
        
        emit Minted(msg.sender, tokensToMint, msg.value);
    }
    
    /**
    * @dev Burn tokens to get ETH back
    * @param amount The amount of tokens to burn
    */
    function burn(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < amount) revert InsufficientBalance();
        
        // Calculate ETH to return
        uint256 basketValuePerToken = getExtendedBasketValuePerToken();
        uint256 valueInUsd = (amount * basketValuePerToken) / STANDARD_PRECISION;
        
        // Apply burn fee
        uint256 valueAfterFee = (valueInUsd * (BASIS_POINTS - burnFee)) / BASIS_POINTS;
        
        // Convert USD value to ETH
        uint256 ethUsdPrice = getEthUsdPrice();
        uint256 ethUsdPriceExtended = ethUsdPrice * PRECISION_FACTOR;
        uint256 ethToReturn = (valueAfterFee * STANDARD_PRECISION) / ethUsdPriceExtended;
        
        if (address(this).balance < ethToReturn) revert InsufficientContractBalance();
        
        // Update total basket value
        totalBasketValueInUSD = totalBasketValueInUSD - valueInUsd;
        
        // Burn tokens before transfer to prevent reentrancy
        _burn(msg.sender, amount);
        
        // Return ETH
        (bool success, ) = payable(msg.sender).call{value: ethToReturn}("");
        if (!success) revert EthTransferFailed();
        
        emit Burned(msg.sender, amount, ethToReturn);
    }
    
    /**
    * @dev Get the basket value per token
    * @return The USD value of the basket per token
    */
    function getBasketValuePerToken() public view returns (uint256) {
        // Convert extended precision value to standard precision for compatibility
        uint256 extendedValue = getExtendedBasketValuePerToken();
        return extendedValue / PRECISION_FACTOR;
    }
    
    /**
    * @dev Get the basket value per token with extended precision
    * @return The USD value of the basket per token
    */
    function getExtendedBasketValuePerToken() public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        
        return (totalBasketValueInUSD * STANDARD_PRECISION) / supply;
    }
    
    /**
    * @dev Calculate the value of the basket in USD with extended precision
    * @return The USD value of the basket
    */
    function calculateExtendedBasketValueInUSD() public view returns (uint256) {
        // Get asset prices in USD (Chainlink returns prices with 8 decimals)
        uint256 goldPriceUsd = uint256(getGoldPrice());
        uint256 btcPriceUsd = uint256(getBtcPrice());
        uint256 usdcPriceUsd = uint256(getUsdcPrice());
        
        // Scale all prices to extended precision
        goldPriceUsd = goldPriceUsd * PRICE_FEED_DECIMALS * PRECISION_FACTOR;
        btcPriceUsd = btcPriceUsd * PRICE_FEED_DECIMALS * PRECISION_FACTOR;
        usdcPriceUsd = usdcPriceUsd * PRICE_FEED_DECIMALS * PRECISION_FACTOR;
        
        // Calculate basket value with extended precision
        uint256 goldValue = (goldPriceUsd * goldPercentage) / BASIS_POINTS;
        uint256 btcValue = (btcPriceUsd * btcPercentage) / BASIS_POINTS;
        uint256 usdcValue = (usdcPriceUsd * usdcPercentage) / BASIS_POINTS;
        
        return goldValue + btcValue + usdcValue;
    }
    
    /**
    * @dev Calculate the value of the basket in USD
    * @return The USD value of the basket
    */
    function calculateBasketValueInUSD() public view returns (uint256) {
        return calculateExtendedBasketValueInUSD() / PRECISION_FACTOR;
    }
    
}