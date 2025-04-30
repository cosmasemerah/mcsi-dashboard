# Memecrime Scene Investigation (MCSI) Dashboard

**🕵️‍♀️ Investigating Rug Pulls, Honeypots, and Insider Exits on Solana Meme Coins**

**Live Dashboard:** [MCSI Dashboard](https://dune.com/satoshi_builder/mcsi)

## Overview

This Dune dashboard provides tools to analyze the Solana meme coin landscape, focusing on identifying potential risks associated with new token launches. It combines market-wide aggregated views with a deep-dive analysis tool for specific tokens launched on Pump.fun, Raydium Launchpad, and Gofundmeme.

Built for the Superteam Earn Bounty: [SuperTeam](https://earn.superteam.fun/listing/memecrime-scene-investigation-dashboard/)

## Dashboard Structure

The dashboard is organized into two main sections:

1.  **Market Overview:** High-level statistics and trends across recent token launches.
2.  **Token Deep Dive Analysis:** Detailed investigation modules for a specific token address entered by the user.

## How to Use

1.  **Market Overview:** Explore the charts and tables to understand recent launch activity, volume distributions, bot presence, and potential serial deployers.
2.  **Token Deep Dive:** Navigate to this section and enter a valid Solana Token Mint Address into the `token_mint_address` parameter field. _(Optional)_ Enter another address in the `wallet_to_track` field to analyze its specific token flow. Click "Run" on the Dune dashboard to populate the modules below.

## Modules Explained

### Market Overview

- **🚀 New Tokens Launched (Last 24h):**
  - **Query:** `queries/aggregated/01_new_tokens_24h.sql` (Query ID: 5055041)
  - **Logic:** Lists tokens detected via creation events/mints on Pump.fun, Raydium, and Gofundmeme within the past 24 hours. Includes basic metadata and creator address.
- **💰 Volume Brackets (Last 7d):**
  - **Query:** `queries/aggregated/02_volume_brackets_7d.sql` (Query ID: 5049561)
  - **Logic:** Calculates the total DEX USD volume (`dex_solana.trades`) for tokens launched in the last 7 days. Groups tokens by launchpad and volume bracket (e.g., '< $1k', '$1k-$5k', etc.) to show market distribution. Tokens with no DEX volume are explicitly marked.
- **🤖 Daily Bot Volume % (Last 30d):**
  - **Query:** `queries/aggregated/03_daily_bot_volume_pct_30d.sql` (Query ID: 5049584)
  - **Logic:** Compares total daily USD volume from `dex_solana.trades` with volume from known bot wallets in `dex_solana.bot_trades` to estimate the percentage of daily volume potentially attributable to bots.
- **🔄 Potential Serial Deployers (Last 90d):**
  - **Query:** `queries/aggregated/04_serial_deployers_90d.sql` (Query ID: 5049593)
  - **Logic:** Identifies wallets that have created more than 2 tokens across the monitored platforms in the last 90 days. Lists the deployment count, timeframe, platforms used, and deployed tokens for each flagged wallet.

### Token Deep Dive Analysis

_(Activated by the `token_mint_address` parameter)_

- **Header - Token Info:**
  - **Query:** `queries/per_token/00_token_info.sql` (Query ID: 5055174)
  - **Logic:** Fetches basic metadata (Name, Symbol, Platform, Creator) for the selected token.
- **Module 1 & 2: 💸 Creator Wallet Activity:**
  - **Creator Fund Flow Table:**
    - **Query:** `queries/per_token/M1_1_creator_fund_flow.sql` (Query ID: 5043463)
    - **Logic:** Tracks all transfers involving the creator's wallet post-creation. Correlates transfers with DEX trades based on `tx_id` to categorize actions (Mint, Burn, DEX Sell/Buy, Transfer In/Out). Shows amounts and USD values.
  - **Creator Outflow (First 24h %) KPI:**
    - **Query:** `queries/per_token/M1_2_creator_outflow_pct_24h.sql` (Query ID: 5009117)
    - **Logic:** Calculates (Total Amount Transferred OUT by Creator in 24h) / (Total Minted Supply) \* 100. High outflow might indicate dumping.
  - **First Creator DEX Sell Table:**
    - **Query:** `queries/per_token/M2_1_first_creator_sell.sql` (Query ID: 5027465)
    - **Logic:** Finds the earliest `block_time` in `dex_solana.trades` where the `trader_id` is the creator and the `token_sold_mint_address` matches the input token, occurring after `creation_time`. Retrieves details of that first sell.
  - **Time to First Sell KPI:**
    - **Query:** `queries/per_token/M2_2_time_to_first_sell.sql` (Query ID: 5027519)
    - **Logic:** Calculates the time difference between `creation_time` and the `first_sell_time` from the previous query. Short times can be a red flag.
- **Optional: 🔍 Track Specific Wallet Fund Flow:**
  - **Query:** `queries/per_token/Track_Wallet_Fund_Flow.sql`
  - **Logic:** Allows users to input an additional wallet address (`{{wallet_to_track}}`) to see a detailed breakdown of the selected token's movements involving that specific wallet. Similar to the Creator Fund Flow, it categorizes transactions (DEX Sell/Buy, Transfer In/Out, etc.) relative to the tracked wallet. _Note: This view is optimized to show activity within the last 30 days._
  - **Usage:** Enter a token address and a wallet address to track in the dashboard parameters. The corresponding table will populate.
- **Module 3: 📈📉 Price & Volume Anomalies:**
  - **Query:** `queries/per_token/M3_price_volume_anomalies.sql` (Query ID: 5009192)
  - **Logic:** Aggregates `dex_solana.trades` per minute. Calculates VWAP price and total USD volume. Uses `LAG()` to find minute-over-minute price change, flagging drops >90%. Uses `AVG()` and `STDDEV_POP()` over a 60-minute rolling window to calculate average volume and standard deviation, flagging volume spikes > (Avg + 3\*StdDev).
- **Module 4: 👥 Ownership Concentration:**
  - **Top Holders Table & Pie Chart:**
    - **Query:** `queries/per_token/M4_1_ownership_distribution.sql` (Query ID: 5027555)
    - **Logic:** Uses `solana_utils.latest_balances` to get current holder balances. Calculates total supply from these balances. Ranks holders and calculates ownership percentage for the Top 10 (or 100 in query, limited in viz). Flags the creator wallet. High concentration in the top wallets is a risk factor.
  - **Creator Current Holding % KPI:**
    - **Query:** `queries/per_token/M4_2_creator_holding_pct.sql` (Query ID: 5053768)
    - **Logic:** Specifically fetches the creator's current balance from `solana_utils.latest_balances` and divides by the total supply calculated from all holders.
- **Module 5: 🤖 Market Maker (MM) Heuristics:**
  - **Round Number Trades Table:**
    - **Query:** `queries/per_token/M5_1_mm_round_trades.sql` (Query ID: 5027632)
    - **Logic:** Counts trades per trader (last 30d) where the raw token amount is divisible by 1,000,000 (heuristic for potential MM activity). Filters for traders with >5 such trades. Joins with `dex_solana.bot_trades` to flag known bot users.
  - **Hourly Frequency Table:**
    - **Query:** `queries/per_token/M5_2_mm_hourly_frequency.sql` (Query ID: 5027665)
    - **Logic:** Aggregates trades per trader per hour (last 7d). Filters for hours where a trader had >10 trades AND their buy/sell ratio was between 0.5 and 2.0 (heuristic for balanced, high-frequency MM activity). Also flags if the trader is a known bot user.
- **Module 6: ⚡ Volume Bot Heuristics:**
  - **Trades Per Second Table:**
    - **Query:** `queries/per_token/M6_1_bot_trades_per_second.sql` (Query ID: 5019979)
    - **Logic:** Counts trades per trader per second (last 24h). Filters for traders with >1 trade in the same second (heuristic for bot activity).

## Data Sources

Primary data sources include:

- `pumpdotfun_solana`, `raydium_solana` decoded tables
- `tokens_solana.transfers`, `tokens_solana.fungible`
- `dex_solana.trades`, `dex_solana.bot_trades`
- `solana_utils.latest_balances`
- `labels.addresses`

## Limitations & Future Work

- Heuristics for MM and Bot detection are initial estimates and may require refinement.
- DEX migration detection is simplified (using a 1-hour delay in M1). More precise detection could be added.
- LP analysis (pulling liquidity) is not yet included but is a key "Post-Rug Indicator" for future versions.
- Coverage depends on Dune's decoding and data availability for specific DEXs and launchpads.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
