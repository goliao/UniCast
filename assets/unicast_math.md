# UniCast


## Off-chain data input and compute
1. Forecasted volatility
    - data input:
        - poolId
        - new fee from implied volatility
    - Compute (offchain):
        - convert updateTime to blockNumber
        - compute fee from impVol 
    - stored as:
        - a mapping from
            - poolId
        - to
            - fee
 2. Forecasted path
     - data input:
         - poolId
         - updateTime
         - growthRate (expressed as a gross return)
     - Compute (offchain):
         - convert updateTime to blockNumber
         - compute new lowerTick, upperTick based on growthRate (and volatility)
    - stored as:
        - a mapping from
            - poolId
        - to
            - lowerTick
            - upperTick (if changing position range)
            - liquidityDelta 



## On-chain compute:
1. Forecasted volatility: there should not be additional on-chain compute since fee updates are provided by oracle.
2. Forecasted path: liquidityDelta needs to be calculated for modifyLiquidity based on the total liquidity of the prior position and the shift in position range.

## Dynamic fees

Fees can be priced as a function of option implied vol $i_v$. Under risk-neutral pricing, fees for event risk should breakeven with expected price movement, that is $E[|r_{t+1}|]$. In option pricing, this is given by the price of a straddle, which is approximately 
$$p_{straddle}=\sqrt{\frac{2}{\pi}}\sigma,$$
where $\sigma$ is the the period specific volatility.

Suppose each period is 12 second (1 ethereum block), $\sigma_{12sec}=\sigma_{annual}/\sqrt(365*24*60*5).$

For Ethereum, $\sigma_{annual}$ has been around 80\%. This means that fee would be $\sqrt{\frac{2}{\pi}}0.80/\sqrt(365*24*60*5)\approx 4 bps$. Not a bad approximation for why 5 bps pool is the bulk of the liquidity for ETH-USDx pairs.

We can extract $\sigma_{annual}$ from any options market (Deribit, Panoptics, Opyn) or forecast using historical volatility around certain events. We can then approximately set the fee to the price of straddle based on the implied vol as detailed above. This can be done off-chain and only the fee needs to be fed by the keeper oracles.






## LP position rebalancing
positions are given by:
- lowertick
- uppertick
- liquidity
- salt

Amount of tokens in each LP position can be backed out given lower, upper ticks, liquidity, and current price by: 

1.	Amount of Token0 (amount0):
$\text{amount0} = \frac{L \times (\sqrt{P_u} - \sqrt{P_l})}{\sqrt{P_c} \times \sqrt{P_u}}$

2.	Amount of Token1 (amount1):
 $\text{amount1} = L \times (\sqrt{P_c} - \sqrt{P_l})$

Where:

- $L$  is the liquidity of the position.
- $P_c$  is the current price (ratio) of token1 in terms of token0.
- $P_l$  is the price at the lower tick.
- $P_u$  is the price at the upper tick.

Prices are the price of token1 in terms of token0. Therefore, portfolio value in units of token0 is 
$$v(L,P_c,P_l,P_u)=amount0+amount1*P_c$$

Rebalance action by itself should not change the price of the portfolio. Otherwise, LP can just create value out of rebalancing.

Suppose $P_l$ and $P_u$ both increase by 10\% and L and $P_c$ remain constant, amount0 and amount1 will both change by the corresponding amounts according to the formula above. The vault would need to settle the balance by depositing/withdrawing the change in amount0 and amoount1. This requires a swap. And the portfolio value would change since $P_c$ is the same unless $\Delta amount0=-\Delta amount1*P_c$, a counterfactural. 

Same value of portfolio before and after reblancing requires:

$$\Delta amount0=- \Delta amount1*P_c,$$

That is,

$$\frac{\Delta L \times (\sqrt{P_u} - \sqrt{P_l})}{\sqrt{P_c} \times \sqrt{P_u}}=-(\Delta L \times (\sqrt{P_c} - \sqrt{P_l}))*P_c,$$

which simplifies to

$$\sqrt{P_u} = \frac{\sqrt{P_l} P_c \sqrt{P_c} + \sqrt{P_l}}{1 - P_c^2}.$$

This means that if we shift $P_l$ by say a certain growth rate, $P_u$ would most likely not shift by as much without modifying the current price changing.  

Assuming $P_c$ is unchanged, one can change the Liquidity such that 

$$v(L',P_c,P_l',P_u')=v(L,P_c,P_l,P_u),$$
where $'$ denote new values.

I.e., we calculate $L'-L$ for `modifiedliquidity.liquidityDelta` based on the new $P_l'$ and $P_u'$ values. We'll still have different amount0 and amount1 which requires swaps. Also when we swap, we'll have a different $P_c$ as a result of the swap. We can approximate this, but in reality the amount of $\Delta P_c$ depends on the total liquidity of the pool, i.e. amount of LPs outside of the vault.


**Suppose the impact of the swap is infintisimal, that is $P_c'=P_c$,** then we need to solve the following $v'(.')=v(.)$ equation for $L'$ given $P_u$, $P_l$,$P_u'$, $P_l'$, $L$, and $P_c$. That is,

<!-- $$\frac{L \times (\sqrt{P_u} - \sqrt{P_l})}{\sqrt{P_c} \times \sqrt{P_u}} + P_c * (L \times (\sqrt{P_c} - \sqrt{P_l}))=\frac{L' \times (\sqrt{P_u'} - \sqrt{P_l'})}{\sqrt{P_c} \times \sqrt{P_u'}} + P_c * (L' \times (\sqrt{P_c} - \sqrt{P_l'}))
$$
 -->
$$
\begin{align}
    &\frac{L \times (\sqrt{P_u} - \sqrt{P_l})}{\sqrt{P_c} \times \sqrt{P_u}} + P_c \cdot (L \times (\sqrt{P_c} - \sqrt{P_l})) \notag \\
    & = \frac{L' \times (\sqrt{P_u'} - \sqrt{P_l'})}{\sqrt{P_c} \times \sqrt{P_u'}} + P_c \cdot (L' \times (\sqrt{P_c} - \sqrt{P_l'})) \notag
\end{align}
$$
 
 Simplifying, we get
 
$$L{\prime} = L \times \frac{\left( \frac{\sqrt{P_u} - \sqrt{P_l}}{\sqrt{P_c} \sqrt{P_u}} + P_c \times (\sqrt{P_c} - \sqrt{P_l}) \right)}{\left( \frac{\sqrt{P_u{\prime}} - \sqrt{P_l{\prime}}}{\sqrt{P_c} \sqrt{P_u{\prime}}} + P_c \times (\sqrt{P_c} - \sqrt{P_l{\prime}}) \right)}$$


This liquidity delta is right only if there's a lot of other LP liquidity outside of the vault. We can indeed make this the case by artificially adding a large amount of liquidity outside of the vault for demo purpose. 