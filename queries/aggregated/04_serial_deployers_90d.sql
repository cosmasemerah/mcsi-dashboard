-- Market Overview: Potential Serial Deployers (Last 90 Days)
-- Identifies wallets that have created multiple tokens across different platforms

WITH DeploymentsLast90d AS (
    -- Combine token deployments from all platforms
    SELECT creator_wallet_address, token_mint_address, creation_time, platform
    FROM (
        -- Pump.fun deployments
        SELECT
            pc.account_user AS creator_wallet_address,
            pc.account_mint AS token_mint_address,
            pc.call_block_time AS creation_time,
            'Pump.fun' AS platform
        FROM pumpdotfun_solana.pump_call_create pc
        WHERE pc.call_block_time >= now() - interval '90' day

        UNION ALL

        -- Raydium Launchpad deployments
        SELECT
            rl.account_creator AS creator_wallet_address,
            rl.account_base_mint AS token_mint_address,
            rl.call_block_time AS creation_time,
            'Raydium Launchpad' AS platform
        FROM raydium_solana.raydium_launchpad_call_initialize rl
        WHERE rl.call_block_time >= now() - interval '90' day

        UNION ALL

        -- Gofundmeme deployments (first mint event per token)
        SELECT creator_wallet_address, token_mint_address, creation_time, 'Gofundmeme' AS platform
        FROM (
            SELECT
                tst.tx_signer AS creator_wallet_address,
                tst.token_mint_address,
                tst.block_time AS creation_time,
                ROW_NUMBER() OVER (PARTITION BY tst.token_mint_address ORDER BY tst.block_time ASC, tst.block_slot ASC, tst.outer_instruction_index ASC, tst.inner_instruction_index ASC) as rn
            FROM tokens_solana.transfers tst
            WHERE tst.action = 'mint'
              AND tst.outer_executing_account = 'GFMioXjhuDWMEBtuaoaDPJFPEnL2yDHCWKoVPhj1MeA7'
              AND tst.from_token_account IS NULL
              AND tst.block_time >= now() - interval '90' day
        ) fm WHERE rn = 1
    ) all_deployments
),

DeployerStats AS (
    -- Calculate statistics for each deployer
    SELECT
        creator_wallet_address,
        COUNT(DISTINCT token_mint_address) AS deployment_count,
        MIN(creation_time) AS first_deployment_time,
        MAX(creation_time) AS last_deployment_time,
        array_agg(DISTINCT platform) AS platforms_used,
        array_agg(token_mint_address) AS deployed_tokens
    FROM DeploymentsLast90d
    GROUP BY creator_wallet_address
    -- Filter for deployers with more than 2 tokens
    HAVING COUNT(DISTINCT token_mint_address) > 2
)

-- Final select: Join with labels and order by deployment count
SELECT
    ds.creator_wallet_address,
    COALESCE(l.name, ds.creator_wallet_address) AS deployer_label,
    ds.deployment_count,
    ds.first_deployment_time,
    ds.last_deployment_time,
    ds.platforms_used,
    ds.deployed_tokens
FROM DeployerStats ds
LEFT JOIN labels.addresses l
    ON from_base58(ds.creator_wallet_address) = l.address
    AND l.blockchain = 'solana'
ORDER BY
    ds.deployment_count DESC, ds.last_deployment_time DESC;