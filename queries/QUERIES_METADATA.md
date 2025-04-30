# SQL Queries Metadata

This file maps query names/IDs to their corresponding file paths in the repository.

## Market Overview Queries (Aggregated)

- `01_new_tokens_24h.sql` - Lists new tokens launched in the last 24 hours
- `02_volume_brackets_7d.sql` - Shows volume distribution for tokens launched in last 7 days
- `03_daily_bot_volume_pct_30d.sql` - Calculates daily bot volume percentage over last 30 days
- `04_serial_deployers_90d.sql` - Identifies potential serial token deployers in last 90 days

## Token Deep Dive Queries (Per Token)

- `00_token_info.sql` - Basic token metadata and information
- `M1_1_creator_fund_flow.sql` - Tracks creator wallet's token movements
- `M1_2_creator_outflow_pct_24h.sql` - Calculates creator's outflow percentage in first 24h
- `M2_1_first_creator_sell.sql` - Details of creator's first DEX sell
- `M2_2_time_to_first_sell.sql` - Time elapsed until creator's first Dex sell
- `M3_price_volume_anomalies.sql` - Detects price and volume anomalies
- `M4_1_ownership_distribution.sql` - Shows token ownership distribution
- `M4_2_creator_holding_pct.sql` - Calculates creator's current holding percentage
- `M5_1_mm_round_trades.sql` - Identifies potential market maker activity
- `M5_2_mm_hourly_frequency.sql` - Analyzes trading frequency patterns
- `M6_1_bot_trades_per_second.sql` - Detects potential bot trading activity
- `Track_Wallet_Fund_Flow.sql` - Tracks token flow for a specific user-defined wallet (Last 30d)
