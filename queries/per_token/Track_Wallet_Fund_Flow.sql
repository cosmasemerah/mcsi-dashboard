-- Wallet Fund Flow Tracker (Optimized with 30-Day Filter)
-- Parameters:
--   {{token_mint_address}} (Text) - The mint address of the token to track
--   {{wallet_to_track}} (Text) - The wallet address whose flows are being tracked

WITH TokenContext AS (
    -- CTE to fetch creation_time using embedded Helper Query logic
    -- (No time filter here, needs to find potentially older creation times)
    SELECT creation_time
    FROM (
        -- Start of Embedded Helper Query Logic
        WITH PumpTokens AS (
            SELECT pc.call_block_time AS creation_time, pc.account_mint AS token_mint_address
            FROM pumpdotfun_solana.pump_call_create pc WHERE pc.account_mint = '{{token_mint_address}}'
        ), RaydiumTokens AS (
            SELECT rl.call_block_time AS creation_time, rl.account_base_mint AS token_mint_address
            FROM raydium_solana.raydium_launchpad_call_initialize rl WHERE rl.account_base_mint = '{{token_mint_address}}'
        ), GofundmeTokens AS (
            SELECT creation_time, token_mint_address FROM (
                SELECT tst.block_time AS creation_time, tst.token_mint_address,
                       ROW_NUMBER() OVER (PARTITION BY tst.token_mint_address ORDER BY tst.block_time ASC, tst.block_slot ASC, tst.outer_instruction_index ASC, tst.inner_instruction_index ASC) as rn
                FROM tokens_solana.transfers tst
                WHERE tst.token_mint_address = '{{token_mint_address}}' AND tst.action = 'mint' AND tst.outer_executing_account = 'GFMioXjhuDWMEBtuaoaDPJFPEnL2yDHCWKoVPhj1MeA7' AND tst.from_token_account IS NULL
            ) fm WHERE rn = 1
        ), CombinedTokenContext AS (
            SELECT creation_time, token_mint_address FROM PumpTokens UNION ALL
            SELECT creation_time, token_mint_address FROM RaydiumTokens UNION ALL
            SELECT creation_time, token_mint_address FROM GofundmeTokens
        )
        SELECT creation_time FROM CombinedTokenContext WHERE token_mint_address = '{{token_mint_address}}' LIMIT 1
        -- End of Embedded Helper Query Logic
    )
),

TokenDecimals AS (
    -- Fetch decimals for the target token
    SELECT COALESCE(decimals, 0) AS decimals
    FROM tokens_solana.fungible
    WHERE token_mint_address = '{{token_mint_address}}'
    LIMIT 1
),

DexTxUsdValue AS (
    -- Get total USD value from related DEX trades involving the tracked wallet in the same transaction
    SELECT
        tx_id,
        SUM(amount_usd) as tx_total_usd
    FROM dex_solana.trades
    INNER JOIN TokenContext tc ON trader_id = '{{wallet_to_track}}' AND block_time >= tc.creation_time
    WHERE (token_bought_mint_address = '{{token_mint_address}}' OR token_sold_mint_address = '{{token_mint_address}}')
      AND amount_usd IS NOT NULL AND amount_usd > 0
      -- *** OPTIMIZATION: Added 30-day filter ***
      AND block_time >= now() - interval '30' day
    GROUP BY tx_id
),

WalletTransfers AS (
    -- Get all transfers involving the tracked wallet after creation time AND within last 30 days
    SELECT
        t.block_time,
        t.tx_id,
        t.from_owner,
        t.to_owner,
        t.amount,
        t.amount_usd AS transfer_amount_usd,
        dtu.tx_total_usd,
        CASE WHEN dtu.tx_id IS NOT NULL THEN true ELSE false END as is_dex_related_transfer,
        CASE
            WHEN t.from_owner = '{{wallet_to_track}}' THEN 'Outflow'
            WHEN t.to_owner = '{{wallet_to_track}}' THEN 'Inflow'
        END as flow_direction
    FROM tokens_solana.transfers t
    INNER JOIN TokenContext tc ON t.block_time >= tc.creation_time -- Ensure transfer happened after creation
    LEFT JOIN DexTxUsdValue dtu ON t.tx_id = dtu.tx_id
    WHERE t.token_mint_address = '{{token_mint_address}}'
      AND (t.from_owner = '{{wallet_to_track}}' OR t.to_owner = '{{wallet_to_track}}')
      AND COALESCE(t.amount, 0) > 0
      -- *** OPTIMIZATION: Added 30-day filter ***
      AND t.block_time >= now() - interval '30' day
)

-- Final Selection and Formatting
SELECT
    wt.block_time,
    CASE
        WHEN wt.from_owner IS NULL AND wt.flow_direction = 'Inflow' THEN 'Mint Received'
        WHEN wt.to_owner IS NULL AND wt.flow_direction = 'Outflow' THEN 'Burn Sent'
        WHEN wt.is_dex_related_transfer AND wt.flow_direction = 'Outflow' THEN 'DEX Sell'
        WHEN wt.is_dex_related_transfer AND wt.flow_direction = 'Inflow' THEN 'DEX Buy'
        WHEN NOT wt.is_dex_related_transfer AND wt.flow_direction = 'Outflow' THEN 'Transfer Out'
        WHEN NOT wt.is_dex_related_transfer AND wt.flow_direction = 'Inflow' THEN 'Transfer In'
        ELSE 'Unknown'
    END AS transaction_type,
    CASE
        WHEN wt.flow_direction = 'Inflow' THEN wt.amount / power(10, td.decimals)
        ELSE -wt.amount / power(10, td.decimals)
    END AS token_amount_display,
    CASE
        WHEN wt.flow_direction = 'Inflow' THEN -COALESCE(wt.tx_total_usd, wt.transfer_amount_usd, 0)
        ELSE COALESCE(wt.tx_total_usd, wt.transfer_amount_usd, 0)
    END AS amount_usd,
    COALESCE(l_from.name, wt.from_owner, 'Token Mint') AS sender_label,
    COALESCE(l_to.name, wt.to_owner, 'Token Burn') AS receiver_label,
    wt.tx_id,
    wt.from_owner AS sender_address,
    wt.to_owner AS receiver_address
FROM WalletTransfers wt
CROSS JOIN TokenDecimals td
LEFT JOIN labels.addresses l_from
    ON l_from.address = TRY(from_base58(wt.from_owner))
    AND l_from.blockchain = 'solana'
LEFT JOIN labels.addresses l_to
    ON l_to.address = TRY(from_base58(wt.to_owner))
    AND l_to.blockchain = 'solana'
ORDER BY
    wt.block_time DESC