-- Token Deep Dive: Time Between Creation and First Creator Sell
-- Calculates the duration until the creator's first DEX sell

WITH TokenContext AS (
    -- CTE 1: Fetch creator_wallet_address and creation_time using embedded Helper Query logic
    SELECT creator_wallet_address, creation_time
    FROM (
        -- Embedded Helper Query Logic ...
        WITH PumpTokens AS (
            SELECT pc.account_user AS creator_wallet_address, pc.call_block_time AS creation_time
            FROM pumpdotfun_solana.pump_call_create pc WHERE pc.account_mint = '{{token_mint_address}}'
        ), RaydiumTokens AS (
            SELECT rl.account_creator AS creator_wallet_address, rl.call_block_time AS creation_time
            FROM raydium_solana.raydium_launchpad_call_initialize rl WHERE rl.account_base_mint = '{{token_mint_address}}'
        ), GofundmeTokens AS (
            SELECT creator_wallet_address, creation_time FROM (
                SELECT tst.tx_signer AS creator_wallet_address, tst.block_time AS creation_time,
                       ROW_NUMBER() OVER (PARTITION BY tst.token_mint_address ORDER BY tst.block_time ASC, tst.block_slot ASC, tst.outer_instruction_index ASC, tst.inner_instruction_index ASC) as rn
                FROM tokens_solana.transfers tst
                WHERE tst.token_mint_address = '{{token_mint_address}}' AND tst.action = 'mint' AND tst.outer_executing_account = 'GFMioXjhuDWMEBtuaoaDPJFPEnL2yDHCWKoVPhj1MeA7' AND tst.from_token_account IS NULL
            ) fm WHERE rn = 1
        ), CombinedTokenContext AS (
            SELECT creator_wallet_address, creation_time FROM PumpTokens UNION ALL
            SELECT creator_wallet_address, creation_time FROM RaydiumTokens UNION ALL
            SELECT creator_wallet_address, creation_time FROM GofundmeTokens
        )
        SELECT creator_wallet_address, creation_time FROM CombinedTokenContext LIMIT 1
    )
),
FirstCreatorSell AS (
    -- CTE 2: Find the first sell time for the creator AFTER creation
    SELECT
        tc.creator_wallet_address,
        MIN(t.block_time) as first_sell_time -- Only need the minimum time here
    FROM TokenContext tc
    INNER JOIN dex_solana.trades t
        ON t.trader_id = tc.creator_wallet_address
    WHERE t.token_sold_mint_address = '{{token_mint_address}}'
      AND t.block_time >= tc.creation_time -- Optimization filter
    GROUP BY tc.creator_wallet_address
)
-- Final Select: Join context and first sell time, calculate difference
SELECT
    tc.creator_wallet_address,
    tc.creation_time,
    fcs.first_sell_time, -- This will be NULL if no sell occurred due to LEFT JOIN
    -- Calculate difference in seconds
    date_diff('second', tc.creation_time, fcs.first_sell_time) AS time_to_first_sell_seconds,
    -- Calculate difference as an interval type (more human-readable)
    fcs.first_sell_time - tc.creation_time AS time_to_first_sell_interval
FROM TokenContext tc
-- LEFT JOIN is crucial: ensures we get a result even if the creator hasn't sold yet
LEFT JOIN FirstCreatorSell fcs ON tc.creator_wallet_address = fcs.creator_wallet_address