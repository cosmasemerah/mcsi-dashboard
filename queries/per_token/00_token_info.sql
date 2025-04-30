-- Token Deep Dive: Basic Token Information
-- Fetches metadata for a specific token from all supported platforms

WITH PumpTokens AS (
    -- Get token info from Pump.fun creation event
    SELECT
        pc.call_block_time AS creation_time,
        pc.account_mint AS token_mint_address,
        COALESCE(NULLIF(pc.name, ''), 'N/A') AS token_name,
        COALESCE(NULLIF(pc.symbol, ''), 'N/A') AS token_symbol,
        COALESCE(NULLIF(pc.uri, ''), 'N/A') AS token_uri,
        pc.account_user AS creator_wallet_address,
        'Pump.fun' AS platform
    FROM pumpdotfun_solana.pump_call_create pc
    WHERE pc.account_mint = '{{token_mint_address}}'
),
RaydiumTokens AS (
    -- Get token info from Raydium Launchpad creation event
    -- Note: Metadata is fetched separately from fungible table
    SELECT
        rl.call_block_time AS creation_time,
        rl.account_base_mint AS token_mint_address,
        CAST(NULL AS VARCHAR) AS token_name,
        CAST(NULL AS VARCHAR) AS token_symbol,
        CAST(NULL AS VARCHAR) AS token_uri,
        rl.account_creator AS creator_wallet_address,
        'Raydium Launchpad' AS platform
    FROM raydium_solana.raydium_launchpad_call_initialize rl
    WHERE rl.account_base_mint = '{{token_mint_address}}'
),
GofundmeTokens AS (
    -- Get token info from Gofundmeme first mint event
    SELECT
        creation_time,
        token_mint_address,
        CAST(NULL AS VARCHAR) AS token_name,
        CAST(NULL AS VARCHAR) AS token_symbol,
        CAST(NULL AS VARCHAR) AS token_uri,
        creator_wallet_address,
        'Gofundmeme' AS platform
    FROM (
        -- Subquery to get first mint event per token
        -- Uses ROW_NUMBER to ensure we get the earliest mint
        SELECT
            tst.block_time AS creation_time,
            tst.token_mint_address,
            tst.tx_signer AS creator_wallet_address,
            ROW_NUMBER() OVER (PARTITION BY tst.token_mint_address ORDER BY tst.block_time ASC, tst.block_slot ASC, tst.outer_instruction_index ASC, tst.inner_instruction_index ASC) as rn
        FROM tokens_solana.transfers tst
        WHERE
            tst.token_mint_address = '{{token_mint_address}}'
            AND tst.action = 'mint'
            AND tst.outer_executing_account = 'GFMioXjhuDWMEBtuaoaDPJFPEnL2yDHCWKoVPhj1MeA7'
            AND tst.from_token_account IS NULL
    ) first_mints
    WHERE rn = 1
),
CombinedInfo AS (
    -- Combine token info from all platforms
    SELECT creation_time, token_mint_address, token_name, token_symbol, token_uri, creator_wallet_address, platform FROM PumpTokens
    UNION ALL
    SELECT creation_time, token_mint_address, token_name, token_symbol, token_uri, creator_wallet_address, platform FROM RaydiumTokens
    UNION ALL
    SELECT creation_time, token_mint_address, token_name, token_symbol, token_uri, creator_wallet_address, platform FROM GofundmeTokens
)
-- Final select: Join with fungible table to get metadata if not available from creation event
SELECT
    ci.creation_time,
    ci.token_mint_address,
    COALESCE(NULLIF(ci.token_name, ''), NULLIF(tsf.name, ''), 'N/A') AS token_name,
    COALESCE(NULLIF(ci.token_symbol, ''), NULLIF(tsf.symbol, ''), 'N/A') AS token_symbol,
    COALESCE(NULLIF(ci.token_uri, ''), NULLIF(tsf.token_uri, ''), 'N/A') AS token_uri,
    ci.creator_wallet_address,
    ci.platform
FROM CombinedInfo ci
LEFT JOIN tokens_solana.fungible tsf ON ci.token_mint_address = tsf.token_mint_address
WHERE ci.token_mint_address = '{{token_mint_address}}'
LIMIT 1 -- Ensure only one row is returned for the specific token