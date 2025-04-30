-- Token Deep Dive: Potential MM ID via Round Number Trades
-- Identifies traders frequently using round number amounts

WITH AggregatedRoundTrades AS (
    -- CTE 1: Count round-number trades per trader in the last 30 days
    SELECT
        t.trader_id,
        COUNT(*) as round_trade_count
    FROM dex_solana.trades t
    WHERE (
        -- Filter for trades involving the target token
        t.token_bought_mint_address = '{{token_mint_address}}'
        OR t.token_sold_mint_address = '{{token_mint_address}}'
    )
    AND (
        -- Filter for "round number" trades involving the target token
        -- Heuristic: Raw amount is perfectly divisible by 1,000,000
        (t.token_bought_mint_address = '{{token_mint_address}}'
         AND t.token_bought_amount_raw % 1000000 = 0)
        OR
        (t.token_sold_mint_address = '{{token_mint_address}}'
         AND t.token_sold_amount_raw % 1000000 = 0)
    )
    AND t.block_time >= now() - interval '30' day -- Time filter for relevance
    GROUP BY t.trader_id
    -- Filter for traders with a significant number of round trades
    HAVING COUNT(*) > 5 -- Heuristic threshold: More than 5 round trades
),
RecentBotUsers AS (
    -- CTE 2: Get distinct users from the known bot trades table (last 30d)
    SELECT DISTINCT user
    FROM dex_solana.bot_trades
    WHERE blockchain = 'solana'
      AND block_time >= now() - interval '30' day -- Match the timeframe
)
-- Final Select: Join round traders with labels and bot user list
SELECT
    art.trader_id,
    COALESCE(l.name, art.trader_id) AS trader_label, -- Get label or use address
    art.round_trade_count,
    -- Flag if this trader ID also appears in the bot_trades table
    CASE WHEN rbu.user IS NOT NULL THEN true ELSE false END AS is_bot_user
FROM AggregatedRoundTrades art
LEFT JOIN labels.addresses l -- Join for general labels
    ON from_base58(art.trader_id) = l.address
    AND l.blockchain = 'solana'
LEFT JOIN RecentBotUsers rbu -- Join to check if the trader is a known bot user
    ON art.trader_id = rbu.user
ORDER BY
    art.round_trade_count DESC -- Show most frequent round traders first
LIMIT 100 -- Limit results for dashboard performance