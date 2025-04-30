-- Market Overview: Daily Bot Volume Percentage (Last 30 Days)
-- Compares total daily volume with bot volume to estimate bot activity

WITH DailyTotalVolume AS (
    -- Calculate total daily volume from all trades
    SELECT
        date_trunc('day', block_time) AS day,
        COALESCE(SUM(amount_usd), 0) AS total_daily_volume_usd
    FROM dex_solana.trades
    WHERE block_time >= now() - interval '30' day
      AND blockchain = 'solana'
      AND amount_usd IS NOT NULL
    GROUP BY 1
),
DailyBotVolume AS (
    -- Calculate daily volume from known bot trades
    SELECT
        date_trunc('day', block_time) AS day,
        COALESCE(SUM(amount_usd), 0) AS daily_bot_volume_usd
    FROM dex_solana.bot_trades
    WHERE block_time >= now() - interval '30' day
      AND blockchain = 'solana'
      AND amount_usd IS NOT NULL
    GROUP BY 1
)
-- Final select: Calculate bot volume percentage
SELECT
    dtv.day,
    dtv.total_daily_volume_usd,
    COALESCE(dbv.daily_bot_volume_usd, 0) AS daily_bot_volume_usd,
    -- Calculate percentage, handling division by zero
    TRY((COALESCE(dbv.daily_bot_volume_usd, 0) * 100.0) / NULLIF(dtv.total_daily_volume_usd, 0)) AS bot_volume_percentage
FROM DailyTotalVolume dtv
LEFT JOIN DailyBotVolume dbv ON dtv.day = dbv.day
ORDER BY dtv.day DESC;