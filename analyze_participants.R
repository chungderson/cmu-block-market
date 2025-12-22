library(readr)
library(dplyr)
library(lubridate)
library(ggplot2)
library(scales)
library(gridExtra)
library(grid)

# Load data
df <- read_csv("cmu_block_market_transactions.csv", show_col_types = FALSE)
df$timestamp <- with_tz(force_tz(as_datetime(df$timestamp), "UTC"), "America/New_York")

# Filter valid transactions
df_clean <- df %>%
  filter(price > 0, quantity > 0) %>%
  mutate(unit_price = price / quantity) %>%
  filter(unit_price <= 15)

# Anonymize users
all_users <- unique(c(df_clean$buyer, df_clean$seller))
user_map <- data.frame(
  username = all_users,
  anon_id = paste0("User_", sprintf("%04d", seq_along(all_users)))
)

df_anon <- df_clean %>%
  left_join(user_map, by = c("buyer" = "username")) %>%
  rename(buyer_id = anon_id) %>%
  left_join(user_map, by = c("seller" = "username")) %>%
  rename(seller_id = anon_id) %>%
  select(-buyer, -seller)

# --- 1. Buyer Statistics ---
buyer_stats <- df_anon %>%
  group_by(buyer_id) %>%
  summarise(
    total_spent = sum(price),
    total_tx = n(),
    total_blocks = sum(quantity),
    avg_price_per_block = mean(unit_price),
    .groups = "drop"
  ) %>%
  arrange(desc(total_spent))

median_spent <- median(buyer_stats$total_spent)
mean_spent <- mean(buyer_stats$total_spent)

# Distribution of spending
p1 <- ggplot(buyer_stats, aes(x = total_spent)) +
  geom_histogram(fill = "#3498db", color = "white", bins = 50, alpha = 0.8) +
  geom_vline(xintercept = median_spent, color = "#e74c3c", linetype = "dashed", linewidth = 1) +
  scale_x_continuous(labels = dollar_format(), trans = "log10") +
  annotate("text", x = median_spent * 1.5, y = max(table(cut(log10(buyer_stats$total_spent), 50))), 
           label = paste("Median:", dollar(median_spent)), color = "#e74c3c", hjust = 0) +
  labs(
    title = "Distribution of Total Spending per Buyer",
    subtitle = paste0("Median: $", round(median_spent, 2), " | Mean: $", round(mean_spent, 2)),
    x = "Total Amount Spent ($, log scale)",
    y = "Number of Buyers"
  ) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold"))

ggsave("buyer_spending_distribution.png", p1, width = 10, height = 6, dpi = 300)

# Top buyers
top_buyers <- buyer_stats %>%
  head(15) %>%
  mutate(buyer_id = factor(buyer_id, levels = rev(buyer_id)))

p2 <- ggplot(top_buyers, aes(x = buyer_id, y = total_spent)) +
  geom_col(fill = "#3498db", alpha = 0.8) +
  coord_flip() +
  scale_y_continuous(labels = dollar_format(), expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "Top 15 Buyers by Total Spending",
    subtitle = "Anonymized participants",
    x = "",
    y = "Total Spent ($)"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold"),
    axis.text.y = element_text(size = 9)
  )

ggsave("top_buyers.png", p2, width = 10, height = 7, dpi = 300)

# --- 2. Seller Statistics ---
seller_stats <- df_anon %>%
  group_by(seller_id) %>%
  summarise(
    total_earned = sum(price),
    total_tx = n(),
    total_blocks_sold = sum(quantity),
    avg_price_per_block = mean(unit_price),
    .groups = "drop"
  ) %>%
  arrange(desc(total_earned))

top_sellers <- seller_stats %>%
  head(15) %>%
  mutate(seller_id = factor(seller_id, levels = rev(seller_id)))

p3 <- ggplot(top_sellers, aes(x = seller_id, y = total_earned)) +
  geom_col(fill = "#27ae60", alpha = 0.8) +
  coord_flip() +
  scale_y_continuous(labels = dollar_format(), expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "Top 15 Sellers by Total Earnings",
    subtitle = "Anonymized participants",
    x = "",
    y = "Total Earned ($)"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold"),
    axis.text.y = element_text(size = 9)
  )

ggsave("top_sellers.png", p3, width = 10, height = 7, dpi = 300)

# Combined top participants
top_buyers_combined <- buyer_stats %>%
  head(10) %>%
  mutate(type = "Buyer", value = total_spent, id = buyer_id) %>%
  select(id, type, value)

top_sellers_combined <- seller_stats %>%
  head(10) %>%
  mutate(type = "Seller", value = total_earned, id = seller_id) %>%
  select(id, type, value)

top_participants <- bind_rows(top_buyers_combined, top_sellers_combined) %>%
  mutate(id = factor(id, levels = unique(id[order(value, decreasing = TRUE)])))

p4 <- ggplot(top_participants, aes(x = reorder(id, value), y = value, fill = type)) +
  geom_col(alpha = 0.8) +
  coord_flip() +
  facet_wrap(~type, scales = "free_y", ncol = 1) +
  scale_y_continuous(labels = dollar_format(), expand = expansion(mult = c(0, 0.05))) +
  scale_fill_manual(values = c("Buyer" = "#3498db", "Seller" = "#27ae60")) +
  labs(
    title = "Top 10 Market Participants",
    subtitle = "Biggest buyers and sellers (anonymized)",
    x = "Participant ID",
    y = "Total Value ($)"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold"),
    legend.position = "none",
    axis.text.y = element_text(size = 8)
  )

ggsave("top_participants.png", p4, width = 10, height = 8, dpi = 300)

# --- 3. Meal Time Analysis ---
# Breakfast: 6am-10:29:59am EST
# Lunch: 10:30am-4:29:59pm EST  
# Dinner: 4:30pm-12am EST

df_meals <- df_anon %>%
  mutate(
    hour_val = hour(timestamp),
    minute_val = minute(timestamp),
    second_val = second(timestamp),
    time_seconds = hour_val * 3600 + minute_val * 60 + second_val,
    meal_type = case_when(
      time_seconds >= 6 * 3600 & time_seconds < (10 * 3600 + 30 * 60) ~ "Breakfast",
      time_seconds >= (10 * 3600 + 30 * 60) & time_seconds < (16 * 3600 + 30 * 60) ~ "Lunch",
      time_seconds >= (16 * 3600 + 30 * 60) | time_seconds < 6 * 3600 ~ "Dinner",
      TRUE ~ "Other"
    )
  ) %>%
  filter(meal_type != "Other")

# Top consumers by meal type
top_meal_consumers <- df_meals %>%
  group_by(meal_type, buyer_id) %>%
  summarise(blocks_consumed = sum(quantity), .groups = "drop") %>%
  group_by(meal_type) %>%
  slice_max(order_by = blocks_consumed, n = 10) %>%
  mutate(rank = row_number()) %>%
  ungroup()

# Create individual plots for each meal
plot_meal_top <- function(data, meal, color, title_color) {
  d <- data %>% 
    filter(meal_type == meal) %>% 
    arrange(blocks_consumed) %>%
    head(10)
  d$buyer_id <- factor(d$buyer_id, levels = d$buyer_id)
  
  ggplot(d, aes(x = buyer_id, y = blocks_consumed)) +
    geom_col(fill = color, alpha = 0.8) +
    coord_flip() +
    scale_y_continuous(expand = expansion(mult = c(0, 0.05))) +
    labs(
      title = paste("Top 10", meal, "Consumers"),
      subtitle = paste("Total blocks consumed during", meal, "hours"),
      x = "",
      y = "Blocks Consumed"
    ) +
    theme_minimal(base_size = 11) +
    theme(
      plot.title = element_text(face = "bold", color = title_color),
      axis.text.y = element_text(size = 8)
    )
}

p_breakfast <- plot_meal_top(top_meal_consumers, "Breakfast", "#f39c12", "#d68910")
p_lunch <- plot_meal_top(top_meal_consumers, "Lunch", "#e67e22", "#c0392b")
p_dinner <- plot_meal_top(top_meal_consumers, "Dinner", "#34495e", "#2c3e50")

# Combined meal chart
p5 <- grid.arrange(
  p_breakfast, p_lunch, p_dinner,
  ncol = 3,
  top = textGrob("Top Consumers by Meal Time (Anonymized)", 
                 gp = gpar(fontsize = 16, fontface = "bold"))
)

ggsave("top_meal_consumers.png", p5, width = 15, height = 6, dpi = 300)

# Summary statistics by meal
meal_summary <- df_meals %>%
  group_by(meal_type) %>%
  summarise(
    total_blocks = sum(quantity),
    total_transactions = n(),
    unique_buyers = n_distinct(buyer_id),
    avg_price = mean(unit_price),
    .groups = "drop"
  )

p6 <- ggplot(meal_summary, aes(x = reorder(meal_type, total_blocks), y = total_blocks, fill = meal_type)) +
  geom_col(alpha = 0.8) +
  coord_flip() +
  scale_fill_manual(values = c("Breakfast" = "#f39c12", "Lunch" = "#e67e22", "Dinner" = "#34495e")) +
  scale_y_continuous(labels = comma, expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "Total Blocks Consumed by Meal Time",
    subtitle = "Breakfast: 6am-10:29am | Lunch: 10:30am-4:29pm | Dinner: 4:30pm-12am",
    x = "",
    y = "Total Blocks"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold"),
    legend.position = "none"
  )

ggsave("meal_consumption_summary.png", p6, width = 10, height = 5, dpi = 300)

# Print statistics for README
cat("\n=== BUYER STATISTICS ===\n")
cat("Median spending per buyer: $", round(median_spent, 2), "\n")
cat("Mean spending per buyer: $", round(mean_spent, 2), "\n")
cat("Total unique buyers: ", nrow(buyer_stats), "\n")
cat("Top buyer spent: $", round(max(buyer_stats$total_spent), 2), "\n")

cat("\n=== SELLER STATISTICS ===\n")
cat("Total unique sellers: ", nrow(seller_stats), "\n")
cat("Top seller earned: $", round(max(seller_stats$total_earned), 2), "\n")

cat("\n=== MEAL TIME STATISTICS ===\n")
print(meal_summary)

cat("\nCharts created:\n")
cat("- buyer_spending_distribution.png\n")
cat("- top_buyers.png\n")
cat("- top_sellers.png\n")
cat("- top_participants.png\n")
cat("- top_meal_consumers.png\n")
cat("- meal_consumption_summary.png\n")
