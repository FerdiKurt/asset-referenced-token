# BasketToken

BasketToken is an ERC20 token that tracks a weighted basket of assets including gold, BTC, and USDC. The token is collateralized by ETH and uses Chainlink price feeds to maintain its peg to the underlying basket.

## Overview

BasketToken combines the value stability of commodity-backed assets with the transparency and liquidity of cryptocurrency by:

- Tracking a basket composed of gold (40%), BTC (40%), and USDC (20%) by default
- Maintaining price discovery through Chainlink oracles
- Managing collateralization through ETH deposits
- Providing mint and burn functionality with configurable fees
- Implementing precision-focused calculations to minimize value loss

## Features

- **Asset-Backed Stability**: Value derived from a weighted basket of diverse assets
- **Collateralization**: Minimum 120% collateralization ratio by default
- **Decentralized Price Feeds**: Uses Chainlink oracles for reliable price data
- **Customizable Parameters**: Adjustable basket weights, fees, and collateral requirements
- **Enhanced Precision**: Uses extended precision calculations (27 decimals) for accurate valuations

## Technical Details

### Dependencies

- OpenZeppelin Contracts: ERC20 and Ownable implementations
- Chainlink: Price feed oracles for asset pricing

### Key Components

- **Basket Composition**: Configurable weights for gold, BTC, and USDC (default 40/40/20)
- **Price Oracles**: Chainlink price feeds for gold, BTC, USDC, and ETH/USD conversion
- **Mint/Burn Mechanism**: Create tokens by depositing ETH; redeem ETH by burning tokens
- **Fee Structure**: Configurable mint and burn fees (0.5% by default)
- **Precision Management**: Extended precision calculations to minimize value loss

## Functions

### User Functions

- `mint()`: Create new tokens by sending ETH
- `burn(amount)`: Burn tokens to receive ETH back

### View Functions

- `getBasketValuePerToken()`: Calculate the USD value of one token
- `calculateBasketValueInUSD()`: Calculate the USD value of the entire basket
- `getGoldPrice()`, `getBtcPrice()`, `getUsdcPrice()`, `getEthUsdPrice()`: Get current asset prices

### Admin Functions

- `updateBasketComposition(goldPercentage, btcPercentage, usdcPercentage)`: Update basket weights
- `updateFees(mintFee, burnFee)`: Update mint and burn fees
- `updateCollateralRatio(collateralRatio)`: Update required collateralization ratio

## Development and Testing

The project includes comprehensive tests in Foundry that verify:

- Initial state and configuration
- Basket value calculations
- Minting and burning functionality
- Price change scenarios
- Admin functions
- Error handling

### Running Tests

```bash
forge test
```

## Possible Technical Improvements

- **Multi-Collateral Support**: Extend the contract to accept multiple types of collateral beyond ETH
- **Dynamic Basket Rebalancing**: Implement automatic rebalancing mechanisms based on market conditions
- **Governance System**: Add DAO-based governance for decentralized parameter management
- **Liquidity Incentives**: Include liquidity mining rewards to bootstrap adoption
- **Flash Loan Prevention**: Add mechanisms to prevent price manipulation via flash loans
- **Layer 2 Deployment**: Optimize the contract for deployment on Layer 2 solutions for lower gas costs
- **Circuit Breaker**: Implement emergency pause functionality for extreme market conditions
- **Oracle Redundancy**: Add fallback oracle mechanisms to prevent single points of failure
- **External Audits**: Conduct professional security audits before mainnet deployment

## License

SPDX-License-Identifier: UNLICENSED