-- Token Deep Dive: Creator Fund Flow Analysis
-- Tracks all token movements involving the creator's wallet

WITH TokenContext AS (
    -- Get creator wallet and creation time for the token
    SELECT creator_wallet_address, creation_time
    FROM (
        -- Embedded Helper Query Logic to find token context across platforms
        WITH PumpTokens AS (
            SELECT pc.account_user AS creator_wallet_address, pc.call_block_time AS creation_time, pc.account_mint AS token_mint_address
            FROM pumpdotfun_solana.pump_call_create pc WHERE pc.account_mint = '{{token_mint_address}}'
        ), RaydiumTokens AS (
            SELECT rl.account_creator AS creator_wallet_address, rl.call_block_time AS creation_time, rl.account_base_mint AS token_mint_address
            FROM raydium_solana.raydium_launchpad_call_initialize rl WHERE rl.account_base_mint = '{{token_mint_address}}'
        ), GofundmeTokens AS (
            SELECT creator_wallet_address, creation_time, token_mint_address FROM (
                SELECT tst.tx_signer AS creator_wallet_address, tst.block_time AS creation_time, tst.token_mint_address,
                       ROW_NUMBER() OVER (PARTITION BY tst.token_mint_address ORDER BY tst.block_time ASC, tst.block_slot ASC, tst.outer_instruction_index ASC, tst.inner_instruction_index ASC) as rn
                FROM tokens_solana.transfers tst
                WHERE tst.token_mint_address = '{{token_mint_address}}' AND tst.action = 'mint' AND tst.outer_executing_account = 'GFMioXjhuDWMEBtuaoaDPJFPEnL2yDHCWKoVPhj1MeA7' AND tst.from_token_account IS NULL
            ) fm WHERE rn = 1
        ), CombinedTokenContext AS (
            SELECT creator_wallet_address, creation_time, token_mint_address FROM PumpTokens UNION ALL
            SELECT creator_wallet_address, creation_time, token_mint_address FROM RaydiumTokens UNION ALL
            SELECT creator_wallet_address, creation_time, token_mint_address FROM GofundmeTokens
        )
        SELECT creator_wallet_address, creation_time FROM CombinedTokenContext WHERE token_mint_address = '{{token_mint_address}}' LIMIT 1
    )
),
TokenDecimals AS (
    -- Get token decimals for proper amount display
    SELECT COALESCE(decimals, 0) AS decimals
    FROM tokens_solana.fungible
    WHERE token_mint_address = '{{token_mint_address}}'
    LIMIT 1
),
DexTxUsdValue AS (
    -- Calculate total USD value for each DEX transaction involving the creator
    -- This helps identify if a transfer was part of a DEX interaction (buy/sell)
    SELECT
        tx_id,
        SUM(amount_usd) as tx_total_usd
    FROM dex_solana.trades
    INNER JOIN TokenContext tc ON trader_id = tc.creator_wallet_address AND block_time >= tc.creation_time -- Only creator trades post-creation
    WHERE (token_bought_mint_address = '{{token_mint_address}}' OR token_sold_mint_address = '{{token_mint_address}}')
      AND amount_usd IS NOT NULL AND amount_usd > 0
    GROUP BY tx_id
),
CreatorTransfers AS (
    -- Get all token transfers involving the creator's wallet post-creation
    -- Includes both DEX and non-DEX transfers (mints, burns, transfers)
    SELECT
        t.block_time,
        t.tx_id,
        t.from_owner,
        t.to_owner,
        t.amount, -- Raw amount
        t.amount_usd AS transfer_amount_usd, -- USD value directly from transfer table (if available)
        dtu.tx_total_usd, -- Total USD value of the DEX tx (if it was a DEX tx)
        CASE WHEN dtu.tx_id IS NOT NULL THEN true ELSE false END as is_dex_related_transfer, -- Flag based on join with DexTxUsdValue
        CASE
            WHEN t.from_owner = tc.creator_wallet_address THEN 'Outflow'
            WHEN t.to_owner = tc.creator_wallet_address THEN 'Inflow'
        END as flow_direction -- Determine if transfer is into or out of creator wallet
    FROM tokens_solana.transfers t
    INNER JOIN TokenContext tc ON t.block_time >= tc.creation_time -- Ensure transfer is post-creation
    LEFT JOIN DexTxUsdValue dtu ON t.tx_id = dtu.tx_id -- Link transfer to DEX transaction
    WHERE t.token_mint_address = '{{token_mint_address}}'
      AND (t.from_owner = tc.creator_wallet_address OR t.to_owner = tc.creator_wallet_address) -- Only transfers involving creator
      AND COALESCE(t.amount, 0) > 0 -- Exclude zero-amount transfers
)
-- Final select: Format and categorize the transfers
SELECT
    ct.block_time,
    ct.tx_id,
    COALESCE(l_from.name, ct.from_owner, 'Token Mint') AS sender_label, -- Add labels or default descriptions
    COALESCE(l_to.name, ct.to_owner, 'Token Burn') AS receiver_label,
    -- Categorize the transaction type based on context
    CASE
        WHEN ct.from_owner IS NULL AND ct.flow_direction = 'Inflow' THEN 'Mint' -- Creator received from null = Mint
        WHEN ct.to_owner IS NULL AND ct.flow_direction = 'Outflow' THEN 'Burn' -- Creator sent to null = Burn
        WHEN ct.is_dex_related_transfer AND ct.flow_direction = 'Outflow' THEN 'DEX Sell' -- Creator sent, linked to DEX tx
        WHEN ct.is_dex_related_transfer AND ct.flow_direction = 'Inflow' THEN 'DEX Buy' -- Creator received, linked to DEX tx
        WHEN NOT ct.is_dex_related_transfer AND ct.flow_direction = 'Outflow' THEN 'Transfer Out' -- Creator sent, not DEX
        WHEN NOT ct.is_dex_related_transfer AND ct.flow_direction = 'Inflow' THEN 'Transfer In' -- Creator received, not DEX
        ELSE 'Unknown'
    END AS transaction_type,
    -- Calculate display amount, negate for outflow to show directionality
    CASE
        WHEN ct.flow_direction = 'Inflow' THEN ct.amount / power(10, td.decimals)
        ELSE -ct.amount / power(10, td.decimals)
    END AS token_amount_display,
    -- Use DEX tx total USD if available, otherwise use transfer USD value
    -- Negate USD for inflows if desired (though typically USD value is absolute)
    CASE
        WHEN ct.flow_direction = 'Inflow' THEN -COALESCE(ct.tx_total_usd, ct.transfer_amount_usd, 0)
        ELSE COALESCE(ct.tx_total_usd, ct.transfer_amount_usd, 0)
    END AS amount_usd,
    ct.from_owner AS sender_address,
    ct.to_owner AS receiver_address
FROM CreatorTransfers ct
CROSS JOIN TokenDecimals td -- Make decimals available
CROSS JOIN TokenContext tc -- Make context available (though already joined in CTEs)
LEFT JOIN labels.addresses l_from -- Join for sender label
    ON l_from.address = TRY(from_base58(ct.from_owner)) -- Use TRY for safety with from_base58
    AND l_from.blockchain = 'solana'
LEFT JOIN labels.addresses l_to -- Join for receiver label
    ON l_to.address = TRY(from_base58(ct.to_owner))
    AND l_to.blockchain = 'solana'
ORDER BY
    ct.block_time DESC, ct.tx_id -- Show most recent first