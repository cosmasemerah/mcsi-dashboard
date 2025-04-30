-- Market Overview: Volume Distribution for Tokens Launched in Last 7 Days
-- Groups tokens by launchpad and volume bracket to show market distribution

WITH PumpTokens AS (
    -- Get Pump.fun tokens created in last 7 days
    SELECT
        call_block_time AS creation_time,
        account_mint AS token_mint_address,
        'Pump.fun' AS launchpad
    FROM pumpdotfun_solana.pump_call_create
    WHERE call_block_time >= now() - interval '7' day
),

RaydiumTokens AS (
    -- Get Raydium Launchpad tokens created in last 7 days
    SELECT
        call_block_time AS creation_time,
        account_base_mint AS token_mint_address,
        'Raydium Launchpad' AS launchpad
    FROM raydium_solana.raydium_launchpad_call_initialize
    WHERE call_block_time >= now() - interval '7' day
),

GofundmeTokens AS (
    -- Get Gofundmeme tokens created in last 7 days
    SELECT
        block_time AS creation_time,
        token_mint_address,
        'Gofundmeme' AS launchpad
    FROM tokens_solana.transfers
    WHERE action = 'mint'
        AND outer_executing_account = 'GFMioXjhuDWMEBtuaoaDPJFPEnL2yDHCWKoVPhj1MeA7'
        AND block_time >= now() - interval '7' day
        AND from_token_account IS NULL
    GROUP BY 1, 2, 3
),

CombinedNewTokens AS (
    -- Combine all new tokens from different platforms
    SELECT token_mint_address, launchpad FROM PumpTokens
    UNION ALL
    SELECT token_mint_address, launchpad FROM RaydiumTokens
    UNION ALL
    SELECT token_mint_address, launchpad FROM GofundmeTokens
),

TokenVolumes AS (
    -- Calculate total USD volume for each token
    -- Note: We need to check both bought and sold sides to get complete volume
    SELECT
        token_bought_mint_address AS token_mint_address,
        SUM(amount_usd) AS total_volume_usd
    FROM dex_solana.trades
    WHERE block_time >= now() - interval '7' day
        AND token_bought_mint_address IN (SELECT token_mint_address FROM CombinedNewTokens)
    GROUP BY token_bought_mint_address
    UNION ALL
    SELECT
        token_sold_mint_address AS token_mint_address,
        SUM(amount_usd) AS total_volume_usd
    FROM dex_solana.trades
    WHERE block_time >= now() - interval '7' day
        AND token_sold_mint_address IN (SELECT token_mint_address FROM CombinedNewTokens)
    GROUP BY token_sold_mint_address
),

TokenVolumeBrackets AS (
    -- Assign volume brackets based on total USD volume
    SELECT
        cnt.launchpad,
        cnt.token_mint_address,
        CASE
            WHEN COALESCE(tv.total_volume_usd, 0) = 0 THEN 'No DEX Volume'
            WHEN tv.total_volume_usd < 1000 THEN '< $1k'
            WHEN tv.total_volume_usd < 5000 THEN '$1k - $5k'
            WHEN tv.total_volume_usd < 10000 THEN '$5k - $10k'
            WHEN tv.total_volume_usd < 50000 THEN '$10k - $50k'
            WHEN tv.total_volume_usd < 100000 THEN '$50k - $100k'
            ELSE '> $100k'
        END AS volume_bracket
    FROM CombinedNewTokens AS cnt
    LEFT JOIN (
        -- Aggregate total volume from both bought and sold sides
        SELECT token_mint_address, SUM(total_volume_usd) AS total_volume_usd
        FROM TokenVolumes
        GROUP BY token_mint_address
    ) AS tv ON cnt.token_mint_address = tv.token_mint_address
)

-- Final select: Count tokens in each bracket per launchpad
SELECT
    launchpad,
    volume_bracket,
    COUNT(DISTINCT token_mint_address) AS token_count
FROM TokenVolumeBrackets
GROUP BY launchpad, volume_bracket
ORDER BY
    launchpad,
    -- Custom ordering for volume brackets
    CASE volume_bracket
        WHEN 'No DEX Volume' THEN 0
        WHEN '< $1k' THEN 1
        WHEN '$1k - $5k' THEN 2
        WHEN '$5k - $10k' THEN 3
        WHEN '$10k - $50k' THEN 4
        WHEN '$50k - $100k' THEN 5
        WHEN '> $100k' THEN 6
        ELSE 7
    END