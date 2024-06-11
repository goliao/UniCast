# UniCast

UniCast is a forward-looking dynamic Uniswap v4 hook that applied event-based and market-implied volatility to adjust LPfees and LP positions.


### Context:
Volatilities rise predictably during expected events like CPI releases, Fed rate announcements, SEC ETF approval dates, and TradFi “off-market” hours.
Price changes are predictable and LP “impermanent losses” are permanent for tokens with coupon payments, such as liquid staking rebasing, bond coupons, and equity dividends.

### Problem:
Arbitrageurs capture all expected price and volatility changes at the expense of LPs.
These predictable arbitrages harm liquidity, lead to MEV leaks, and deter swappers due to poor liquidity

### Solution: 
UniCast: A hook that adjusts LP fees and positions by incorporating:
Forward-looking volatility to enable dynamic fees and shift value capture from arbs to LPs
Forward-looking price changes to rebalance LP positions


**Features**:
- Improving LP return using forward-looking events and expected price dynamics rebalancing/fee.
- Reduce informed trading (and MEV in the dex context) during known events is something that all tradfi market makers do, and this hook bring this tradfi practice to on-chain dex
- Anticipate and preposition toward future events and expected pricing dynamics:
1) Economic news release schedule, e.g. CPI, NFPR, Fed interest rate decisions 1b) Crypto-specific events, e.g. ETF approval announcement, policy votes
2) Forward-looking volatility implied by options market (Deribit, Panoptics, Opyn)
3) Yield-bearing assets rebalancing, e.g. StETH/ETH pool, USDY/USDC pool

**Details**
[See Slides on UniCast for more details](assets/Slides.pdf)


**Implementation**
[Implementation](assets/diagram.png)

**UI**
[UI](assets/UI.jpg)



