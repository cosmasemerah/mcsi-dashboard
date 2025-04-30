-- Token Deep Dive: Price Drop & Volume Spike Anomaly Detection
-- Analyzes minute-by-minute DEX price/volume for anomalies

WITH MinuteStats AS (
    -- CTE 1: Calculate minute-by-minute VWAP price and volume
    SELECT
        date_trunc('minute', block_time) AS minute,
        SUM(amount_usd) AS volume_usd,
        SUM( -- Sum token amounts based on whether it was bought or sold
            CASE
                WHEN token_bought_mint_address = '{{token_mint_address}}' THEN token_bought_amount
                WHEN token_sold_mint_address = '{{token_mint_address}}' THEN token_sold_amount
                ELSE 0
            END
        ) AS volume_token,
        -- Calculate VWAP Price: Total USD / Total Token Volume
        TRY(SUM(amount_usd) / SUM(
            CASE
                WHEN token_bought_mint_address = '{{token_mint_address}}' THEN token_bought_amount
                WHEN token_sold_mint_address = '{{token_mint_address}}' THEN token_sold_amount
                ELSE 0
            END
        )) AS price
    FROM dex_solana.trades
    WHERE
        (token_bought_mint_address = '{{token_mint_address}}' OR token_sold_mint_address = '{{token_mint_address}}')
        AND block_time >= NOW() - INTERVAL '7' day -- Look at recent data
    GROUP BY 1 -- Group by minute
),
RollingMetrics AS (
    -- CTE 2: Calculate previous minute's price and rolling 60-min volume stats
    SELECT
        minute,
        price,
        volume_usd,
        volume_token,
        -- Get price from the previous minute using LAG window function
        LAG(price, 1) OVER (ORDER BY minute ASC) AS previous_minute_price,
        -- Calculate rolling 60-minute average volume
        AVG(volume_usd) OVER (ORDER BY minute ASC ROWS BETWEEN 59 PRECEDING AND CURRENT ROW) AS rolling_avg_volume_usd,
        -- Calculate rolling 60-minute population standard deviation of volume
        STDDEV_POP(volume_usd) OVER (ORDER BY minute ASC ROWS BETWEEN 59 PRECEDING AND CURRENT ROW) AS rolling_stddev_volume_usd
    FROM MinuteStats
),
AnomalyFlags AS (
    -- CTE 3: Determine boolean flags for price drops (>90%) and volume spikes (> avg + 3*stddev)
    SELECT
        minute,
        price,
        previous_minute_price,
        volume_usd,
        volume_token,
        rolling_avg_volume_usd,
        rolling_stddev_volume_usd,
        -- Flag price drop if current price is < 10% of previous price
        CASE
            WHEN price IS NOT NULL
                 AND previous_minute_price IS NOT NULL
                 AND previous_minute_price != 0
                 AND (price / previous_minute_price) < 0.1 -- Drop > 90%
            THEN true
            ELSE false
        END AS is_price_drop_anomaly,
        -- Flag volume spike if current volume > avg + 3*stddev (and stddev > 0)
        CASE
            WHEN volume_usd IS NOT NULL
                 AND rolling_avg_volume_usd IS NOT NULL
                 AND rolling_stddev_volume_usd IS NOT NULL
                 AND rolling_stddev_volume_usd > 0 -- Avoid flagging on flat volume
                 AND volume_usd > (rolling_avg_volume_usd + (3 * rolling_stddev_volume_usd))
            THEN true
            ELSE false
        END AS is_volume_spike_anomaly
    FROM RollingMetrics
)
-- Final Select: Calculate price change %, output metrics and flags
SELECT
    minute,
    price,
    previous_minute_price,
    -- Calculate price change percentage, handle null/zero previous price
    TRY(((price / NULLIF(previous_minute_price, 0)) - 1) * 100) AS price_change_percentage,
    is_price_drop_anomaly,
    volume_usd,
    volume_token,
    rolling_avg_volume_usd,
    rolling_stddev_volume_usd,
    is_volume_spike_anomaly,
    -- Helper columns for visualization: show value only if anomaly flag is true
    CASE WHEN is_price_drop_anomaly THEN price ELSE NULL END AS price_at_anomaly,
    CASE WHEN is_volume_spike_anomaly THEN volume_usd ELSE NULL END AS volume_at_anomaly
FROM AnomalyFlags
ORDER BY
    minute ASC -- Order chronologically