-- Token Deep Dive: Creator Outflow Percentage (First 24h)
-- Calculates % of total supply transferred OUT by creator in first 24h

WITH TokenContext AS (
    -- CTE 1: Fetch creation_time and creator_wallet_address using embedded Helper Query logic
    SELECT creation_time, creator_wallet_address
    FROM (
        -- Embedded Helper Query Logic ...
        WITH PumpTokens AS (
            SELECT pc.call_block_time AS creation_time, pc.account_mint AS token_mint_address, pc.account_user AS creator_wallet_address
            FROM pumpdotfun_solana.pump_call_create pc WHERE pc.account_mint = '{{token_mint_address}}'
        ), RaydiumTokens AS (
            SELECT rl.call_block_time AS creation_time, rl.account_base_mint AS token_mint_address, rl.account_creator AS creator_wallet_address
            FROM raydium_solana.raydium_launchpad_call_initialize rl WHERE rl.account_base_mint = '{{token_mint_address}}'
        ), GofundmeTokens AS (
            SELECT creation_time, token_mint_address, creator_wallet_address FROM (
                SELECT tst.block_time AS creation_time, tst.token_mint_address, tst.tx_signer AS creator_wallet_address, ROW_NUMBER() OVER (PARTITION BY tst.token_mint_address ORDER BY tst.block_time ASC, tst.block_slot ASC, tst.outer_instruction_index ASC, tst.inner_instruction_index ASC) as rn
                FROM tokens_solana.transfers tst
                WHERE tst.token_mint_address = '{{token_mint_address}}' AND tst.action = 'mint' AND tst.outer_executing_account = 'GFMioXjhuDWMEBtuaoaDPJFPEnL2yDHCWKoVPhj1MeA7' AND tst.from_token_account IS NULL
            ) fm WHERE rn = 1
        ), Combined AS (
            SELECT creation_time, token_mint_address, creator_wallet_address FROM PumpTokens UNION ALL
            SELECT creation_time, token_mint_address, creator_wallet_address FROM RaydiumTokens UNION ALL
            SELECT creation_time, token_mint_address, creator_wallet_address FROM GofundmeTokens
        )
        SELECT creation_time, creator_wallet_address FROM Combined WHERE token_mint_address = '{{token_mint_address}}' LIMIT 1
    )
),
TokenMetadata AS (
    -- CTE 2: Fetch token decimals for calculations
    SELECT COALESCE(decimals, 0) AS decimals
    FROM tokens_solana.fungible
    WHERE token_mint_address = '{{token_mint_address}}'
    LIMIT 1
),
TotalSupply AS (
    -- CTE 3: Calculate total supply based on summing mint actions
    SELECT COALESCE(SUM(amount), 0) AS total_supply_raw
    FROM tokens_solana.transfers
    WHERE token_mint_address = '{{token_mint_address}}'
    AND action = 'mint'
    AND from_owner IS NULL -- Ensure it's a true mint action
),
CreatorOutflow AS (
    -- CTE 4: Calculate raw amount transferred *from* the creator within the first 24 hours
    SELECT COALESCE(SUM(t.amount), 0) AS creator_outflow_24h_raw
    FROM tokens_solana.transfers t
    INNER JOIN TokenContext tc ON t.from_owner = tc.creator_wallet_address -- Filter for transfers FROM creator
    WHERE
        t.token_mint_address = '{{token_mint_address}}'
        -- block_time filter for first 24 hours
        AND t.block_time >= tc.creation_time
        AND t.block_time < tc.creation_time + interval '24' hour
        AND t.to_owner IS NOT NULL -- Exclude burns initiated by creator
)
-- Final Calculation and Output
SELECT
    tc.creator_wallet_address,
    -- Apply decimals to calculated raw supply
    ts.total_supply_raw / power(10, tm.decimals) AS total_supply_display,
    -- Apply decimals to calculated raw outflow
    co.creator_outflow_24h_raw / power(10, tm.decimals) AS creator_outflow_24h_display,
    -- Calculate percentage: (outflow / supply) * 100
    -- Use TRY and NULLIF for safety against division by zero or potential overflows
    TRY((CAST(co.creator_outflow_24h_raw AS DOUBLE) * 100.0) / NULLIF(ts.total_supply_raw, 0)) AS creator_outflow_percentage
FROM
    -- CROSS JOIN CTEs as each should produce a single row of summary data for the token
    TokenContext tc,
    TokenMetadata tm,
    TotalSupply ts,
    CreatorOutflow co