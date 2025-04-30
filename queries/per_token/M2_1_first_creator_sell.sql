-- Token Deep Dive: First Creator DEX Sell
-- Finds the details of the first DEX sell tx by the creator

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
    -- CTE 2: Find the first sell transaction details by the creator AFTER creation
    SELECT
        tc.creator_wallet_address,
        MIN(t.block_time) as first_sell_time, -- Find the earliest sell time
        MIN_BY(t.tx_id, t.block_time) as first_sell_tx_id, -- Get tx_id corresponding to MIN block_time
        MIN_BY(t.amount_usd, t.block_time) as first_sell_amount_usd, -- Get amount_usd for that tx
        MIN_BY(t.token_sold_amount, t.block_time) as first_sell_token_amount -- Get token amount for that tx
    FROM TokenContext tc
    INNER JOIN dex_solana.trades t
        ON t.trader_id = tc.creator_wallet_address -- Join based on creator wallet trading
    WHERE t.token_sold_mint_address = '{{token_mint_address}}' -- Ensure it's a sell of the target token
      AND t.block_time >= tc.creation_time -- Optimization: Only look at trades after creation
    GROUP BY tc.creator_wallet_address -- Group to apply MIN/MIN_BY for the specific creator
)
-- Final output: Display details of the first sell
SELECT
    creator_wallet_address,
    first_sell_time,
    first_sell_tx_id,
    first_sell_amount_usd,
    -first_sell_token_amount AS first_sell_token_amount -- Negate token amount to show it as an outflow/sell
FROM FirstCreatorSell