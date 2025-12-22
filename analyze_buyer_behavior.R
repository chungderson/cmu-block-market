library(readr)
library(dplyr)
library(lubridate)
library(ggplot2)
library(gridExtra)
library(grid) # Added for textGrob
library(stringr)

# Load data
df <- read_csv("cmu_block_market_transactions.csv", show_col_types = FALSE)
df$timestamp <- with_tz(force_tz(as_datetime(df$timestamp), "UTC"), "America/New_York")

# Filter valid
df_clean <- df %>%
  filter(price > 0, quantity > 0) %>%
  filter(hour(timestamp) >= 6)

# Anonymize
all_users <- unique(c(df_clean$buyer, df_clean$seller))
user_map <- data.frame(
  username = all_users,
  anon_id = paste0("User_", seq_along(all_users))
)

df_anon <- df_clean %>%
  left_join(user_map, by = c("buyer" = "username")) %>%
  rename(buyer_id = anon_id) %>%
  left_join(user_map, by = c("seller" = "username")) %>%
  rename(seller_id = anon_id)

# --- 1. Buyer Statistics ---
buyer_stats <- df_anon %>%
  group_by(buyer_id) %>%
  summarise(
    total_spent = sum(price),
    total_tx = n(),
    total_blocks = sum(quantity),
    avg_price = mean(price/quantity)
  )

median_spent <- median(buyer_stats$total_spent)
mean_spent <- mean(buyer_stats$total_spent)

p1 <- ggplot(buyer_stats, aes(x = total_spent)) +
  geom_histogram(fill = "steelblue", color = "white", bins = 50) +
  scale_x_log10(labels = scales::dollar_format()) +
  labs(
    title = "Distribution of Total Spending per Buyer (Log Scale)",
    subtitle = paste0("Median Spent: $", round(median_spent, 2)),
    x = "Total Amount Spent ($)",
    y = "Count of Buyers"
  ) +
  theme_minimal()

ggsave("buyer_spending_distribution.png", p1, width = 8, height = 6)

# --- 2. Meal Time Analysis ---
df_meals <- df_anon %>%
  mutate(
    h = hour(timestamp),
    m = minute(timestamp),
    time_numeric = h + m/60,
    meal_type = case_when(
      time_numeric >= 6 & time_numeric < 10.5 ~ "Breakfast",
      time_numeric >= 10.5 & time_numeric < 16.5 ~ "Lunch",
      time_numeric >= 16.5 ~ "Dinner",
      TRUE ~ "Other"
    )
  ) %>%
  filter(meal_type != "Other")

# Top Buyers by Meal Category
top_meal_buyers <- df_meals %>%
  group_by(meal_type, buyer_id) %>%
  summarise(blocks = sum(quantity), .groups = "drop") %>%
  group_by(meal_type) %>%
  slice_max(order_by = blocks, n = 5) %>%
  mutate(rank = row_number()) %>%
  ungroup()

plot_meal <- function(data, meal, color) {
  d <- data %>% filter(meal_type == meal) %>% arrange(blocks)
  d$buyer_id <- factor(d$buyer_id, levels = d$buyer_id) # Lock sort order
  
  ggplot(d, aes(x = buyer_id, y = blocks)) +
    geom_col(fill = color) +
    coord_flip() +
    labs(title = meal, x = "", y = "Blocks") +
    theme_minimal()
}

p_bk <- plot_meal(top_meal_buyers, "Breakfast", "#f1c40f")
p_ln <- plot_meal(top_meal_buyers, "Lunch", "#e67e22")
p_dn <- plot_meal(top_meal_buyers, "Dinner", "#2c3e50")

png("top_meal_buyers.png", width = 1000, height = 600)
grid.arrange(p_bk, p_ln, p_dn, ncol = 3, top = textGrob("Top Buyers by Meal Time (Anonymized)", gp=gpar(fontsize=16, fontface="bold")))
dev.off()

# --- 3. Biggest Market Participants (Anonymized) ---
top_b <- buyer_stats %>% 
  arrange(desc(total_spent)) %>% 
  head(10) %>%
  mutate(type = "Buyer", value = total_spent, id = buyer_id) %>%
  select(id, type, value)

seller_stats <- df_anon %>%
  group_by(seller_id) %>%
  summarise(total_earned = sum(price)) %>%
  arrange(desc(total_earned)) %>%
  head(10) %>%
  mutate(type = "Seller", value = total_earned, id = seller_id) %>%
  select(id, type, value)

top_participants <- bind_rows(top_b, seller_stats)

p3 <- ggplot(top_participants, aes(x = reorder(id, value), y = value, fill = type)) +
  geom_col() +
  coord_flip() +
  facet_wrap(~type, scales = "free_y") +
  scale_y_continuous(labels = scales::dollar_format()) +
  scale_fill_manual(values = c("Buyer" = "steelblue", "Seller" = "darkgreen")) +
  labs(
    title = "Biggest Market Whales (Anonymized)",
    subtitle = "Top 10 Buyers (Spent) and Sellers (Earned)",
    x = "Participant ID",
    y = "Total Value ($)"
  ) +
  theme_minimal() +
  theme(legend.position = "none")

ggsave("top_whales_anonymized.png", p3, width = 10, height = 6)

cat("Stats for README:\n")
cat("Median Buyer Spending: $", round(median_spent, 2), "\n")
cat("Mean Buyer Spending: $", round(mean_spent, 2), "\n")
cat("Max Single Buyer Spent: $", max(buyer_stats$total_spent), "\n")
cat("Total Active Buyers:", nrow(buyer_stats), "\n")
