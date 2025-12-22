library(readr)
library(dplyr)
library(ggplot2)
library(lubridate)
library(scales)
library(tidyr)

# Load data
df <- read_csv("cmu_block_market_transactions.csv", show_col_types = FALSE)
df$timestamp <- with_tz(force_tz(as_datetime(df$timestamp), "UTC"), "America/New_York")

# Filter valid transactions
df_clean <- df %>%
  filter(price > 0, quantity > 0) %>%
  mutate(unit_price = price / quantity) %>%
  filter(unit_price <= 15)

# Create anonymization mapping
unique_buyers <- unique(df_clean$buyer)
unique_sellers <- unique(df_clean$seller)

buyer_mapping <- data.frame(
  actual = unique_buyers,
  anon = paste0("Buyer_", 1:length(unique_buyers)),
  stringsAsFactors = FALSE
)

seller_mapping <- data.frame(
  actual = unique_sellers,
  anon = paste0("Seller_", 1:length(unique_sellers)),
  stringsAsFactors = FALSE
)

# Apply anonymization
df_anon <- df_clean %>%
  left_join(buyer_mapping, by = c("buyer" = "actual")) %>%
  left_join(seller_mapping, by = c("seller" = "actual")) %>%
  rename(buyer_anon = anon.x, seller_anon = anon.y) %>%
  select(-buyer, -seller) %>%
  rename(buyer = buyer_anon, seller = seller_anon)

# Add meal time classification
df_anon <- df_anon %>%
  mutate(
    hour = hour(timestamp),
    meal_type = case_when(
      hour >= 6 & hour < 10.5 ~ "Breakfast",
      hour >= 10.5 & hour < 16.5 ~ "Lunch",
      hour >= 16.5 | hour < 6 ~ "Dinner",
      TRUE ~ "Other"
    )
  )

# === BUYER STATISTICS ===
buyer_stats <- df_anon %>%
  group_by(buyer) %>%
  summarise(
    total_spent = sum(price),
    total_blocks = sum(quantity),
    num_transactions = n(),
    avg_price = mean(price)
  ) %>%
  arrange(desc(total_spent))

median_spent <- median(buyer_stats$total_spent)
print(paste("Median money spent per buyer: $", round(median_spent, 2)))

# Top 20 buyers
top_buyers <- buyer_stats %>%
  head(20)

p1 <- ggplot(top_buyers, aes(x = reorder(buyer, total_spent), y = total_spent)) +
  geom_col(fill = "#3498db") +
  coord_flip() +
  scale_y_continuous(labels = dollar_format()) +
  theme_minimal() +
  labs(
    title = "Top 20 Buyers by Total Spending",
    subtitle = paste0("Median spending per buyer: ", dollar(median_spent)),
    x = "",
    y = "Total Amount Spent ($)"
  ) +
  theme(panel.grid.major.y = element_blank())

ggsave("top_buyers.png", p1, width = 10, height = 8)

# === SELLER STATISTICS ===
seller_stats <- df_anon %>%
  group_by(seller) %>%
  summarise(
    total_earned = sum(price),
    total_blocks = sum(quantity),
    num_transactions = n(),
    avg_price = mean(price)
  ) %>%
  arrange(desc(total_earned))

median_earned <- median(seller_stats$total_earned)
print(paste("Median money earned per seller: $", round(median_earned, 2)))

# Top 20 sellers
top_sellers <- seller_stats %>%
  head(20)

p2 <- ggplot(top_sellers, aes(x = reorder(seller, total_earned), y = total_earned)) +
  geom_col(fill = "#e74c3c") +
  coord_flip() +
  scale_y_continuous(labels = dollar_format()) +
  theme_minimal() +
  labs(
    title = "Top 20 Sellers by Total Earnings",
    subtitle = paste0("Median earnings per seller: ", dollar(median_earned)),
    x = "",
    y = "Total Amount Earned ($)"
  ) +
  theme(panel.grid.major.y = element_blank())

ggsave("top_sellers.png", p2, width = 10, height = 8)

# === MEAL TYPE ANALYSIS ===
meal_by_buyer <- df_anon %>%
  group_by(buyer, meal_type) %>%
  summarise(blocks = sum(quantity), .groups = "drop") %>%
  pivot_wider(names_from = meal_type, values_from = blocks, values_fill = 0) %>%
  mutate(total_blocks = Breakfast + Lunch + Dinner)

# Top breakfast consumers
top_breakfast <- meal_by_buyer %>%
  arrange(desc(Breakfast)) %>%
  head(15) %>%
  mutate(buyer = reorder(buyer, Breakfast))

p3 <- ggplot(top_breakfast, aes(x = buyer, y = Breakfast)) +
  geom_col(fill = "#f39c12") +
  coord_flip() +
  theme_minimal() +
  labs(
    title = "Top 15 Breakfast Block Consumers",
    subtitle = "6:00 AM - 10:29 AM EST",
    x = "",
    y = "Blocks Purchased"
  ) +
  theme(panel.grid.major.y = element_blank())

ggsave("top_breakfast_buyers.png", p3, width = 10, height = 7)

# Top lunch consumers
top_lunch <- meal_by_buyer %>%
  arrange(desc(Lunch)) %>%
  head(15) %>%
  mutate(buyer = reorder(buyer, Lunch))

p4 <- ggplot(top_lunch, aes(x = buyer, y = Lunch)) +
  geom_col(fill = "#27ae60") +
  coord_flip() +
  theme_minimal() +
  labs(
    title = "Top 15 Lunch Block Consumers",
    subtitle = "10:30 AM - 4:29 PM EST",
    x = "",
    y = "Blocks Purchased"
  ) +
  theme(panel.grid.major.y = element_blank())

ggsave("top_lunch_buyers.png", p4, width = 10, height = 7)

# Top dinner consumers
top_dinner <- meal_by_buyer %>%
  arrange(desc(Dinner)) %>%
  head(15) %>%
  mutate(buyer = reorder(buyer, Dinner))

p5 <- ggplot(top_dinner, aes(x = buyer, y = Dinner)) +
  geom_col(fill = "#8e44ad") +
  coord_flip() +
  theme_minimal() +
  labs(
    title = "Top 15 Dinner Block Consumers",
    subtitle = "4:30 PM - 12:00 AM EST",
    x = "",
    y = "Blocks Purchased"
  ) +
  theme(panel.grid.major.y = element_blank())

ggsave("top_dinner_buyers.png", p5, width = 10, height = 7)

# === MEAL PREFERENCES OF TOP BUYERS ===
top_20_buyers_list <- top_buyers$buyer

meal_breakdown <- df_anon %>%
  filter(buyer %in% top_20_buyers_list) %>%
  group_by(buyer, meal_type) %>%
  summarise(blocks = sum(quantity), .groups = "drop") %>%
  group_by(buyer) %>%
  mutate(pct = blocks / sum(blocks) * 100)

p6 <- ggplot(meal_breakdown, aes(x = reorder(buyer, -blocks), y = blocks, fill = meal_type)) +
  geom_col() +
  coord_flip() +
  scale_fill_manual(values = c("Breakfast" = "#f39c12", "Lunch" = "#27ae60", "Dinner" = "#8e44ad")) +
  theme_minimal() +
  labs(
    title = "Meal Preferences of Top 20 Buyers",
    subtitle = "Breakdown by time of purchase",
    x = "",
    y = "Blocks Purchased",
    fill = "Meal Type"
  ) +
  theme(panel.grid.major.y = element_blank())

ggsave("top_buyers_meal_breakdown.png", p6, width = 10, height = 8)

# === BUYER SPENDING DISTRIBUTION ===
p7 <- ggplot(buyer_stats, aes(x = total_spent)) +
  geom_histogram(bins = 50, fill = "#2c3e50", color = "white") +
  geom_vline(xintercept = median_spent, color = "#e74c3c", linetype = "dashed", size = 1) +
  annotate("text", x = median_spent * 1.1, y = Inf, 
           label = paste0("Median: ", dollar(median_spent)), 
           vjust = 2, hjust = -0.1, color = "#e74c3c", size = 4) +
  scale_x_continuous(labels = dollar_format(), limits = c(0, 300)) +
  theme_minimal() +
  labs(
    title = "Distribution of Buyer Spending",
    subtitle = paste0(nrow(buyer_stats), " unique buyers"),
    x = "Total Amount Spent ($)",
    y = "Number of Buyers"
  )

ggsave("buyer_spending_distribution.png", p7, width = 10, height = 6)

print("All participant analysis charts created successfully!")
print(paste("Total unique buyers:", nrow(buyer_stats)))
print(paste("Total unique sellers:", nrow(seller_stats)))
print(paste("Median spent per buyer:", dollar(median_spent)))
print(paste("Median earned per seller:", dollar(median_earned)))

