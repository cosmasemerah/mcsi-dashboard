-- Token Deep Dive: Potential MM ID via Hourly Frequency & Ratio
-- Identifies traders with high hourly trades and balanced buy/sell activity

WITH RelevantTrades AS (
    -- CTE 1: Select trades involving the target token within the last 7 days
    SELECT
        date_trunc('hour', block_time) as hour,
        trader_id,
        token_bought_mint_address,
        token_sold_mint_address,
        block_time -- Kept for potential future use, like joining bot trades more precisely
    FROM dex_solana.trades
    WHERE (
        token_bought_mint_address = '{{token_mint_address}}'
        OR token_sold_mint_address = '{{token_mint_address}}'
      )
      AND block_time >= now() - interval '7' day -- Time filter
),
HourlyTraderStats AS (
    -- CTE 2: Aggregate trade counts per trader per hour
    SELECT
        hour,
        trader_id,
        COUNT(*) as hourly_trade_count,
        -- Count buys of the target token
        COUNT(CASE WHEN token_bought_mint_address = '{{token_mint_address}}' THEN 1 END) AS hourly_buy_count,
        -- Count sells of the target token
        COUNT(CASE WHEN token_sold_mint_address = '{{token_mint_address}}' THEN 1 END) AS hourly_sell_count
    FROM RelevantTrades
    GROUP BY hour, trader_id
),
PotentialMMs AS (
    -- CTE 3: Calculate buy/sell ratio and filter for potential MM characteristics
    SELECT
        hour,
        trader_id,
        hourly_trade_count,
        hourly_buy_count,
        hourly_sell_count,
        -- Calculate Buy/Sell ratio, handle division by zero
        TRY(CAST(hourly_buy_count AS double) / NULLIF(hourly_sell_count, 0)) AS hourly_buy_sell_ratio
    FROM HourlyTraderStats
    WHERE
        -- Heuristic 1: High frequency within the hour
        hourly_trade_count > 10
        -- Heuristic 2: Balanced buy/sell ratio (between 0.5 and 2.0)
        AND TRY(CAST(hourly_buy_count AS double) / NULLIF(hourly_sell_count, 0)) BETWEEN 0.5 AND 2.0
),

RecentBotUsers AS (
    -- CTE 4: Get distinct users from the bot trades table (last 7d)
    SELECT DISTINCT user
    FROM dex_solana.bot_trades
    WHERE blockchain = 'solana'
      AND block_time >= now() - interval '7' day -- Match the timeframe
)
-- Final Select: Join potential MMs with labels and bot users
SELECT
    pmm.hour,
    pmm.trader_id,
    COALESCE(l.name, pmm.trader_id) AS trader_label, -- Get label or use address
    pmm.hourly_trade_count,
    pmm.hourly_buy_count,
    pmm.hourly_sell_count,
    pmm.hourly_buy_sell_ratio,
    -- Flag if this trader ID also appears in the bot_trades table
    CASE WHEN rbu.user IS NOT NULL THEN true ELSE false END AS is_bot_user
FROM PotentialMMs pmm
LEFT JOIN labels.addresses l -- Join for general labels
    ON from_base58(pmm.trader_id) = l.address
    AND l.blockchain = 'solana'
LEFT JOIN RecentBotUsers rbu -- Join to check if the trader is a known bot user
    ON pmm.trader_id = rbu.user
ORDER BY
    pmm.hour DESC, pmm.hourly_trade_count DESC -- Show recent and high-frequency intervals first