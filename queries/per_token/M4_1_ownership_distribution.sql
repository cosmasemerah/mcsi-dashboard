-- Token Deep Dive: Current Ownership Distribution (Top 10 Holders)
-- Shows top holders, their % ownership, and flags the creator

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
CurrentHolders AS (
    -- CTE 2: Fetch ALL current non-zero balances from the utility table
    SELECT
        token_balance_owner,
        token_balance -- Raw balance amount
    FROM solana_utils.latest_balances
    WHERE token_mint_address = '{{token_mint_address}}'
      AND token_balance > 0 -- Only consider wallets currently holding the token
),
SupplyInfo AS (
    -- CTE 3: Calculate total supply based on the sum of ALL current non-zero balances
    SELECT
        SUM(token_balance) AS total_supply -- Raw total supply
    FROM CurrentHolders
),
RankedHolders AS (
    -- CTE 4: Rank all holders by their raw balance
    SELECT
        token_balance_owner,
        token_balance,
        ROW_NUMBER() OVER (ORDER BY token_balance DESC) as holder_rank
    FROM CurrentHolders
),
Top10Holders AS (
    -- CTE 5: Select only the top 10 holders based on rank
    -- Note: The query filename indicates Top 100, but the code uses Top 10.
    -- This limits the output for dashboard visualization purposes.
    SELECT
        token_balance_owner,
        token_balance
    FROM RankedHolders
    WHERE holder_rank <= 10
)
-- Final Select: Join Top 10 with labels, calculate percentages using TOTAL supply, flag creator
SELECT
    th.token_balance_owner,
    -- Assign 'Creator' label if match, otherwise use label name or address
    CASE
        WHEN th.token_balance_owner = tc.creator_wallet_address THEN 'Creator'
        ELSE COALESCE(l.name, th.token_balance_owner)
    END AS holder_label,
    th.token_balance, -- Raw balance
    -- Calculate ownership percentage: (Holder Balance / Total Supply) * 100
    TRY((th.token_balance / NULLIF(si.total_supply, 0)) * 100.0) AS ownership_percentage,
    -- Check if the holder is the creator
    CASE
        WHEN th.token_balance_owner = tc.creator_wallet_address THEN true
        ELSE false
    END AS is_creator
FROM Top10Holders th
CROSS JOIN SupplyInfo si -- Makes total_supply available for percentage calculation
CROSS JOIN TokenContext tc -- Makes creator_wallet_address available for flagging
LEFT JOIN labels.addresses l -- Join labels ONLY for the top 10
    ON from_base58(th.token_balance_owner) = l.address -- Convert address for join
    AND l.blockchain = 'solana'
ORDER BY
    th.token_balance DESC -- Show largest holders first