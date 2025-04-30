-- Token Deep Dive: Creator Current Holding Percentage (KPI)
-- Calculates the creator's current ownership %

WITH TokenContext AS (
    -- CTE 1: Fetch creator_wallet_address using embedded Helper Query logic
    SELECT creator_wallet_address
    FROM (
        -- Embedded Helper Query Logic ...
        WITH PumpTokens AS (
            SELECT pc.account_user AS creator_wallet_address, pc.account_mint AS token_mint_address
            FROM pumpdotfun_solana.pump_call_create pc WHERE pc.account_mint = '{{token_mint_address}}'
        ), RaydiumTokens AS (
            SELECT rl.account_creator AS creator_wallet_address, rl.account_base_mint AS token_mint_address
            FROM raydium_solana.raydium_launchpad_call_initialize rl WHERE rl.account_base_mint = '{{token_mint_address}}'
        ), GofundmeTokens AS (
            SELECT creator_wallet_address, token_mint_address FROM (
                SELECT tst.tx_signer AS creator_wallet_address, tst.token_mint_address,
                       ROW_NUMBER() OVER (PARTITION BY tst.token_mint_address ORDER BY tst.block_time ASC, tst.block_slot ASC, tst.outer_instruction_index ASC, tst.inner_instruction_index ASC) as rn
                FROM tokens_solana.transfers tst
                WHERE tst.token_mint_address = '{{token_mint_address}}' AND tst.action = 'mint' AND tst.outer_executing_account = 'GFMioXjhuDWMEBtuaoaDPJFPEnL2yDHCWKoVPhj1MeA7' AND tst.from_token_account IS NULL
            ) fm WHERE rn = 1
        ), CombinedTokenContext AS (
            SELECT creator_wallet_address, token_mint_address FROM PumpTokens UNION ALL
            SELECT creator_wallet_address, token_mint_address FROM RaydiumTokens UNION ALL
            SELECT creator_wallet_address, token_mint_address FROM GofundmeTokens
        )
        SELECT creator_wallet_address FROM CombinedTokenContext WHERE token_mint_address = '{{token_mint_address}}' LIMIT 1
    )
),
CurrentHoldersWithPositiveBalance AS (
    -- CTE 2: Fetch ALL current non-zero balances (needed for accurate total supply)
    SELECT
        token_balance_owner,
        token_balance
    FROM solana_utils.latest_balances
    WHERE token_mint_address = '{{token_mint_address}}'
      AND token_balance > 0
),
SupplyInfo AS (
    -- CTE 3: Calculate total supply based on the sum of ALL current non-zero balances
    -- Use COALESCE(..., 1) to avoid division by zero if supply is somehow 0
    SELECT
        COALESCE(SUM(token_balance), 1) AS total_supply
    FROM CurrentHoldersWithPositiveBalance
),
CreatorBalance AS (
    -- CTE 4: Fetch the creator's specific current balance
    SELECT
       COALESCE(token_balance, 0) as creator_token_balance
    FROM solana_utils.latest_balances lb
    INNER JOIN TokenContext tc ON lb.token_balance_owner = tc.creator_wallet_address -- Join on creator address
    WHERE lb.token_mint_address = '{{token_mint_address}}'
)
-- Final Select: Calculate creator's ownership percentage
SELECT
    -- Percentage = (Creator Balance / Total Supply) * 100
    TRY((COALESCE((SELECT creator_token_balance FROM CreatorBalance), 0) / si.total_supply) * 100.0) AS ownership_percentage
FROM SupplyInfo si