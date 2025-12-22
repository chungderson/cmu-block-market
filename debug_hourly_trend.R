library(readr)
library(dplyr)
library(lubridate)

df <- read_csv("cmu_block_market_transactions.csv", show_col_types = FALSE)
df$timestamp <- with_tz(force_tz(as_datetime(df$timestamp), "UTC"), "America/New_York")

# Filter
df_clean <- df %>%
  filter(price > 0, quantity > 0) %>%
  mutate(unit_price = price / quantity) %>%
  filter(unit_price <= 15) %>%
  filter(hour(timestamp) >= 7) # Ignore super early morning outliers

# Average Price by Hour
hourly_trend <- df_clean %>%
  mutate(hour = hour(timestamp)) %>%
  group_by(hour) %>%
  summarise(
    Avg_Price = mean(unit_price),
    Median_Price = median(unit_price),
    Count = n()
  ) %>%
  arrange(hour)

print(hourly_trend, n=24)


