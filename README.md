# CMU Block Market Analysis

An analysis of the Carnegie Mellon University dining block secondary market, where students (primarily first-years, who are obligated to purchase the university meal plan) trade excess meal swipes ("blocks") for cash via Venmo or Zelle through a Discord server.

### Example Market Activity
A snapshot of typical trading in the `#block-market` channel.
![Market Activity](market_activity_example.png)

---
### Market Overview

| Metric | Value |
|--------|------:|
| **Total Transactions** | 21,558 |
| **Total Blocks Traded** | 22,407 |
| **Total Dollar Volume** | $149,629 |
| **Market Duration** | 117 days |
| **Date Range** | Aug 23 – Dec 18, 2025 |

*Note: Outliers (>$15/block) excluded from price analysis.*

### Price Statistics

| Statistic | Value |
|-----------|------:|
| **Mean Price/Block** | $6.73 |
| **Median Price/Block** | $7.00 |
| **Standard Deviation** | $1.72 |
| **Minimum** | $0.50 |
| **Maximum** | $15.00 |
---
## Visual Market Overview

### Daily Candlestick Chart with Volume
OHLC candlestick visualization showing price action and trading volume by day.
![Daily Candlesticks](image.png)

### Price Footprint Heatmap
Daily distribution of transactions by price level. Darker regions represent higher volume. This visualization helps identify price consolidation zones and high-activity price levels over time.
![Footprint Heatmap](price_footprint_heatmap.png)

### 4-Hour Candlestick Chart
Higher granularity view of intraday price movements.
![4H Candlesticks](price_candle_4h_wide.png)

### Volume by Price Level
Total blocks traded at each price point (rounded to nearest $0.50). A nonzero number of blocks were traded at $4.20, $6.70 and $9.11, for whatever reason.
![Volume Discrete](volume_price_discrete.png)

### Activity Heatmap
Visualizing "hot zones" for trading. Yellow indicates low activity, while black indicates high activity.
![Activity Heatmap](heatmap_activity_day_hour.png)

### Top Weeks by Dollar Volume
The end of the semester sees massive trading volume as students with excess blocks attempt to offload them before plans reset.
![Weekly Dollar Volume](dollar_volume_weekly.png)

---

## Market Participants

### Top Buyers & Sellers (Anonymized)
A look at the biggest movers in the market by total dollar volume.
![Top Participants](top_anonymous_participants.png)

### Meal Preferences of Top Buyers
Breakdown of when the top 20 buyers purchase their blocks.
![Meal Breakdown Detailed](top_buyers_meal_breakdown.png)

### Top Buyers by Block Volume
![Top Buyers](top_buyers.png)

### Top Sellers by Earnings
![Top Sellers](top_sellers.png)

---

## Market Statistics

#### Price Distribution (Quartiles)

| Percentile | Price |
|------------|------:|
| 25th (Q1) | $6.00 |
| 50th (Median) | $7.00 |
| 75th (Q3) | $8.00 |
| IQR | $2.00 |

### Participant Demographics

| Role | Count | Median Activity | Median $ | Max $ |
|------|------:|----------------:|---------:|------:|
| **Buyers** | 1,738 | 6 blocks | $39 | $1,634 |
| **Sellers** | 882 | 16 blocks | $97 | $1,772 |

#### Market Concentration
- **Top 10 buyers** account for **6.2%** of total spending
- **Top 10 sellers** account for **8.6%** of total earnings
> The market is relatively decentralized — no single participant dominates.

#### Buyer Spending Distribution

| Percentile | Amount Spent |
|------------|-------------:|
| 25% | $13.00 |
| 50% (Median) | $39.00 |
| 75% | $107.50 |
| 90% | $228.07 |
| 95% | $325.72 |
| 99% | $618.55 |
| Max | $1,633.95 |

*Note: The spending distribution is highly right-skewed (power law), meaning a small number of "power buyers" spend significantly more than the average student. A log scale is typically used to visualize this type of data, but a linear scale is shown below for simplicity.*

### Linear Scale
Most buyers spend <$100, with a long tail of high spenders.
![Buyer Spend Distribution](buyer_spend_distribution.png)

### Log Scale
Applying a log scale reveals the underlying structure of spending habits.
![Buyer Spend Distribution Log](buyer_spend_distribution_log.png)

### Meal Time Breakdown

| Meal | Transactions | % of Market | Avg Price |
|------|-------------:|------------:|----------:|
| **Lunch** (10:30a–4:30p) | 11,434 | 53.0% | $6.82 |
| **Dinner** (4:30p–12a) | 9,838 | 45.6% | $6.66 |
| **Breakfast** (6a–10:30a) | 286 | 1.3% | $5.82 |

> **Insight**: Lunch dominates the market, but dinner commands nearly half of all transactions. Breakfast is negligible.

### Meal Consumption Summary
Total blocks consumed by meal time.
![Meal Consumption](meal_consumption_summary.png)

### Time-Based Patterns

#### Weekday vs Weekend

| Day Type | Transactions | Avg Price | Volume |
|----------|-------------:|----------:|-------:|
| **Weekday** | 17,317 | $6.96 | $123,839 |
| **Weekend** | 4,241 | $5.82 | $25,790 |

> **Weekend Discount**: Prices drop ~16% on weekends ($5.82 vs $6.96 on weekdays).

#### School Break Analysis

Analysis of price behavior during major school breaks (Labor Day, Fall Break, Thanksgiving).

| Period | Avg Price | Avg Daily Volume |
|--------|----------:|-----------------:|
| **Regular Session** | $6.76 | 200 blocks |
| **School Breaks** | $5.57 | 64 blocks |

> **Holiday Discount**: Prices drop **17.72%** and daily trading volume plummets **68%** during school breaks as demand vanishes while supply remains roughly the same (students can fulfill orders through grubhub, regardless of their location).

![Footprint with Breaks](price_footprint_breaks_v2.png)

#### Peak Trading Hours (EST)

| Hour | Transactions | Avg Price |
|------|-------------:|----------:|
| **12 PM** | 3,339 | $7.05 |
| **6 PM** | 2,590 | $6.84 |
| **1 PM** | 2,262 | $6.88 |
| **11 AM** | 2,094 | $6.79 |
| **5 PM** | 2,061 | $6.62 |

![Hourly Volume](hist_transactions_by_hour.png)

![Daily Volume](hist_transactions_by_day.png)

---

## Data Pipeline

```
Discord JSON → process_market.py → CSV → R Analysis → Visualizations
```

1. **Raw Data**: Discord chat exports (JSON)
2. **Processing**: `process_market.py` — regex-based order extraction, troll filtering, transaction matching
3. **Output**: `cmu_block_market_transactions.csv`
4. **Analysis**: R scripts for visualization and statistics

### Transaction Matching Logic
- Prioritizes Discord reply feature for accurate buyer-seller matching
- Falls back to time-proximity matching (< 5 min window)
- Filters out trolls (price > $30, keywords like "trillion")
- Handles "bump" price updates, multi-block orders, and flex additions

---

## Files

| File | Description |
|------|-------------|
| `process_market.py` | Main data processing script |
| `load_data.R` | R data loading helper |
| `market_tearsheet.pdf` | Summary statistics PDF |
| `price_*.png` | Price visualization charts |
| `volume_*.png` | Volume analysis charts |
| `top_*.png` | Participant leaderboards |
| `hist_*.png` | Distribution histograms |
| `heatmap_*.png` | Activity heatmaps |

---

## License

Educational analysis only. Data sourced from public Discord channel.

---

*Analysis by [@chungderson](https://github.com/chungderson)*
