## UniCast

UniCast is a forward-looking dynamic hook that applied event-based and market-implied volatility to affect changes in LPfees and rebalance LP positions via a hook operated vault.

Features:
- Improving LP return using forward-looking events and expected price dynamics rebalancing/fee.
- Reduce informed trading (and MEV in the dex context) during known events is something that all tradfi market makers do, and this hook bring this tradfi practice to on-chain dex
- Anticipate and preposition toward future events and expected pricing dynamics:
1) Economic news release schedule, e.g. CPI, NFPR, Fed interest rate decisions 1b) Crypto-specific events, e.g. ETF approval announcement, policy votes
2) Forward-looking volatility implied by options market (Deribit, Panoptics, Opyn)
3) Yield-bearing assets rebalancing, e.g. StETH/ETH pool, USDY/USDC pool
