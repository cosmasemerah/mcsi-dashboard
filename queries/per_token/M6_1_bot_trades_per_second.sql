-- Token Deep Dive: Potential Volume Bot ID via Trades Per Second
-- Identifies wallets executing multiple trades in the same second

WITH TraderSecondStats AS (
    -- CTE 1: Aggregate trades per trader per second (last 24h)
    SELECT
        date_trunc('second', t.block_time) as second,
        t.trader_id,
        COUNT(*) as trades_per_second
    FROM dex_solana.trades t
    WHERE (
        -- Filter for trades involving the target token
        t.token_bought_mint_address = '{{token_mint_address}}'
        OR t.token_sold_mint_address = '{{token_mint_address}}'
      )
      AND t.block_time >= now() - interval '24' hour -- Time filter
    GROUP BY
        1, 2 -- Group by second and trader_id
    -- Filter for high frequency within the second
    HAVING COUNT(*) > 1 -- Heuristic: More than 1 trade in the same second indicates potential bot
)
-- Final Select: Join potential bots with labels
SELECT
    tss.second,
    tss.trader_id,
    COALESCE(l.name, tss.trader_id) AS trader_label, -- Get label or use address
    tss.trades_per_second
FROM TraderSecondStats tss
LEFT JOIN labels.addresses l
    ON from_base58(tss.trader_id) = l.address -- Convert address for join
    AND l.blockchain = 'solana' -- Ensure we use Solana labels
ORDER BY
    tss.second DESC, tss.trades_per_second DESC -- Show recent and high-frequency intervals first