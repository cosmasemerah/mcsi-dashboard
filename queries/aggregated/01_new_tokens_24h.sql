-- Market Overview: New Tokens Launched in Last 24 Hours
-- Combines token creation events from Pump.fun, Raydium Launchpad, and Gofundmeme

WITH TokenCreations AS (
    -- Pump.fun tokens: Direct creation events with metadata
    SELECT
        call_block_time AS creation_time,
        account_mint AS token_mint_address,
        name AS token_name,
        symbol AS token_symbol,
        uri AS token_uri,
        account_user AS creator_wallet_address,
        account_bondingCurve AS bonding_curve_address,
        'Pump.fun' AS platform,
        call_tx_id AS creation_tx_id
    FROM pumpdotfun_solana.pump_call_create
    WHERE call_block_time >= now() - interval '24' hour

    UNION ALL

    -- Raydium Launchpad tokens: Creation events (metadata fetched separately)
    SELECT
        call_block_time AS creation_time,
        account_base_mint AS token_mint_address,
        CAST(NULL AS VARCHAR) AS token_name,
        CAST(NULL AS VARCHAR) AS token_symbol,
        CAST(NULL AS VARCHAR) AS token_uri,
        account_creator AS creator_wallet_address,
        CAST(NULL AS VARCHAR) AS bonding_curve_address,
        'Raydium Launchpad' AS platform,
        call_tx_id AS creation_tx_id
    FROM raydium_solana.raydium_launchpad_call_initialize
    WHERE call_block_time >= now() - interval '24' hour

    UNION ALL

    -- Gofundmeme tokens: First mint event per token
    SELECT
        creation_time,
        token_mint_address,
        CAST(NULL AS VARCHAR) AS token_name,
        CAST(NULL AS VARCHAR) AS token_symbol,
        CAST(NULL AS VARCHAR) AS token_uri,
        creator_wallet_address,
        CAST(NULL AS VARCHAR) AS bonding_curve_address,
        'GoFundMeme' AS platform,
        creation_tx_id
    FROM (
        -- Subquery to get first mint event per token
        SELECT
            tst.block_time AS creation_time,
            tst.token_mint_address,
            tst.tx_signer AS creator_wallet_address,
            tst.tx_id AS creation_tx_id,
            ROW_NUMBER() OVER (PARTITION BY tst.token_mint_address ORDER BY tst.block_time ASC, tst.block_slot ASC, tst.outer_instruction_index ASC, tst.inner_instruction_index ASC) as rn
        FROM tokens_solana.transfers tst
        WHERE
            tst.outer_executing_account = 'GFMioXjhuDWMEBtuaoaDPJFPEnL2yDHCWKoVPhj1MeA7'
            AND tst.action = 'mint'
            AND tst.block_time >= now() - interval '24' hour
    ) first_mints
    WHERE rn = 1
)
-- Final select: Join with fungible token table to get metadata if not available from creation event
SELECT
    tc.creation_time,
    tc.token_mint_address,
    COALESCE(tc.token_name, tsf.name, 'N/A') AS token_name,
    COALESCE(tc.token_symbol, tsf.symbol, 'N/A') AS token_symbol,
    COALESCE(tc.token_uri, tsf.token_uri, 'N/A') AS token_uri,
    tc.creator_wallet_address,
    tc.platform,
    tc.bonding_curve_address,
    tc.creation_tx_id
FROM TokenCreations tc
LEFT JOIN tokens_solana.fungible tsf ON tc.token_mint_address = tsf.token_mint_address
ORDER BY tc.creation_time DESC;