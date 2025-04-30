# SQL Queries Metadata

This file maps query names/IDs to their corresponding file paths in the repository.

## Market Overview Queries (Aggregated)

- `01_new_tokens_24h.sql` - New tokens created in the last 24 hours
- `02_volume_brackets_7d.sql` - Volume distribution brackets over 7 days
- `03_daily_bot_volume_pct_30d.sql` - Daily bot trading volume percentage over 30 days
- `04_serial_deployers_90d.sql` - Analysis of serial token deployers over 90 days

## Token Deep Dive Queries (Per Token)

- `00_token_info.sql` - Basic token information (Name, Symbol, Creator, Platform)
- `M1_1_creator_fund_flow.sql` - Creator fund flow analysis
- `M1_2_creator_outflow_pct_24h.sql` - Creator outflow percentage in last 24 hours
- `M2_1_first_creator_sell.sql` - First creator sell analysis
- `M2_2_time_to_first_sell.sql` - Time to first sell analysis
- `M3_price_volume_anomalies.sql` - Price and volume anomalies detection
- `M4_1_ownership_distribution.sql` - Token ownership distribution
- `M4_2_creator_holding_pct.sql` - Creator's current holding percentage KPI
- `M5_1_mm_round_trades.sql` - Market maker round trades analysis
- `M5_2_mm_hourly_frequency.sql` - Market maker hourly trading frequency
- `M6_1_bot_trades_per_second.sql` - Bot trading frequency analysis
