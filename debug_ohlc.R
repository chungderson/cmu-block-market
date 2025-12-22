library(readr)
library(dplyr)
library(lubridate)

# Load data
df <- read_csv("cmu_block_market_transactions.csv", show_col_types = FALSE)
df$timestamp <- with_tz(force_tz(as_datetime(df$timestamp), "UTC"), "America/New_York")

# Filter valid
df <- df %>% 
  filter(price > 0, quantity > 0) %>%
  mutate(unit_price = price / quantity) %>%
  filter(unit_price <= 15)

# Analyze Daily OHLC
daily_stats <- df %>%
  mutate(day = as_date(timestamp)) %>%
  group_by(day) %>%
  arrange(timestamp) %>% # CRITICAL: Ensure sorted by time
  summarise(
    Open = first(unit_price),
    Close = last(unit_price),
    High = max(unit_price),
    Low = min(unit_price),
    Transactions = n()
  ) %>%
  mutate(
    Color = ifelse(Close >= Open, "Green", "Red"),
    Change = Close - Open
  )

# Print Summary
cat("Total Days:", nrow(daily_stats), "\n")
cat("Green Days (Close >= Open):", sum(daily_stats$Color == "Green"), "\n")
cat("Red Days (Close < Open):", sum(daily_stats$Color == "Red"), "\n")

# Check if there's a systematic bias
cat("\nSample of Days:\n")
print(head(daily_stats, 10))

# Check intraday sorting of original file
# taking the first day with many transactions
sample_day <- daily_stats$day[1]
cat("\nChecking sorting for:", as.character(sample_day), "\n")
day_data <- df %>% filter(as_date(timestamp) == sample_day)
is_sorted <- !is.unsorted(day_data$timestamp)
cat("Is data chronologically sorted in dataframe by default?", is_sorted, "\n")

