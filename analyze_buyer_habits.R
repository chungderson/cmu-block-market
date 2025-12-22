# Load libraries
if (!require(readr)) install.packages("readr", repos = "http://cran.us.r-project.org")
if (!require(dplyr)) install.packages("dplyr", repos = "http://cran.us.r-project.org")
if (!require(ggplot2)) install.packages("ggplot2", repos = "http://cran.us.r-project.org")
if (!require(lubridate)) install.packages("lubridate", repos = "http://cran.us.r-project.org")
if (!require(gridExtra)) install.packages("gridExtra", repos = "http://cran.us.r-project.org")
if (!require(digest)) install.packages("digest", repos = "http://cran.us.r-project.org")

library(readr)
library(dplyr)
library(ggplot2)
library(lubridate)
library(gridExtra)
library(digest)

# Read Data
df <- read_csv("cmu_block_market_transactions.csv", show_col_types = FALSE)
df$timestamp <- with_tz(force_tz(as_datetime(df$timestamp), "UTC"), "America/New_York")

# Filter valid transactions (Market Hours 6am-12am)
df_market <- df %>%
  filter(price > 0, quantity > 0) %>%
  filter(hour(timestamp) >= 6)

# 1. Anonymize Participants
# Create a mapping for buyers and sellers
all_users <- unique(c(df_market$buyer, df_market$seller))
# Generate consistent anonymous IDs based on rank or hash
# Let's verify rank later, for now just use a deterministic hash or factor level
# Actually, users want to see "Biggest Buyer", so sorting by volume and naming "Buyer 1" is informative.

# Aggregation for Buyer Stats
buyer_stats <- df_market %>%
  group_by(buyer) %>%
  summarise(
    Total_Transactions = n(),
    Total_Blocks = sum(quantity),
    Total_Spent = sum(price),
    Avg_Price = mean(price/quantity)
  ) %>%
  arrange(desc(Total_Spent))

# Assign Anonymous IDs (Buyer 1 is biggest spender)
buyer_stats$Anon_ID <- paste0("Buyer ", 1:nrow(buyer_stats))

# Aggregation for Seller Stats
seller_stats <- df_market %>%
  group_by(seller) %>%
  summarise(
    Total_Transactions = n(),
    Total_Blocks = sum(quantity),
    Total_Earned = sum(price),
    Avg_Price = mean(price/quantity)
  ) %>%
  arrange(desc(Total_Earned))

# Assign Anonymous IDs (Seller 1 is biggest earner)
seller_stats$Anon_ID <- paste0("Seller ", 1:nrow(seller_stats))

# --- Visualization 1: Top Participants (Anonymized) ---
p1 <- ggplot(head(buyer_stats, 15), aes(x = reorder(Anon_ID, Total_Spent), y = Total_Spent)) +
  geom_col(fill = "steelblue") +
  coord_flip() +
  scale_y_continuous(labels = scales::dollar_format()) +
  labs(title = "Top 15 Buyers by Spend", x = "", y = "Total Spent ($)") +
  theme_minimal()

p2 <- ggplot(head(seller_stats, 15), aes(x = reorder(Anon_ID, Total_Earned), y = Total_Earned)) +
  geom_col(fill = "forestgreen") +
  coord_flip() +
  scale_y_continuous(labels = scales::dollar_format()) +
  labs(title = "Top 15 Sellers by Earnings", x = "", y = "Total Earned ($)") +
  theme_minimal()

ggsave("top_anonymous_participants.png", arrangeGrob(p1, p2, ncol = 2), width = 12, height = 6)

# --- Visualization 2: Spend Distribution ---
median_spend <- median(buyer_stats$Total_Spent)
mean_spend <- mean(buyer_stats$Total_Spent)

p3 <- ggplot(buyer_stats, aes(x = Total_Spent)) +
  geom_histogram(fill = "purple", bins = 50, alpha = 0.7) +
  scale_x_log10(labels = scales::dollar_format()) +
  geom_vline(xintercept = median_spend, linetype = "dashed", color = "black") +
  annotate("text", x = median_spend, y = 100, label = paste("Median:", scales::dollar(median_spend)), 
           hjust = -0.1, color = "black") +
  labs(title = "Distribution of Buyer Spending (Log Scale)",
       subtitle = "How much do students spend on blocks?",
       x = "Total Spent (Log Scale)", y = "Count of Buyers") +
  theme_minimal()

ggsave("buyer_spend_distribution.png", p3, width = 8, height = 5)

# --- 3. Meal Time Analysis ---
# Categorize transactions
df_meals <- df_market %>%
  mutate(
    h = hour(timestamp) + minute(timestamp)/60,
    Meal = case_when(
      h >= 6 & h < 10.5 ~ "Breakfast",
      h >= 10.5 & h < 16.5 ~ "Lunch",
      h >= 16.5 ~ "Dinner",
      TRUE ~ "Other"
    )
  )

# Calculate Consumption per Buyer per Meal
meal_stats <- df_meals %>%
  group_by(buyer, Meal) %>%
  summarise(Blocks = sum(quantity), .groups = 'drop') %>%
  left_join(buyer_stats %>% select(buyer, Anon_ID), by = "buyer")

# Top Eaters per Meal
top_breakfast <- meal_stats %>% filter(Meal == "Breakfast") %>% arrange(desc(Blocks)) %>% head(10)
top_lunch <- meal_stats %>% filter(Meal == "Lunch") %>% arrange(desc(Blocks)) %>% head(10)
top_dinner <- meal_stats %>% filter(Meal == "Dinner") %>% arrange(desc(Blocks)) %>% head(10)

# Combine for Plotting
top_meals <- bind_rows(top_breakfast, top_lunch, top_dinner) %>%
  mutate(Meal = factor(Meal, levels = c("Breakfast", "Lunch", "Dinner")))

p4 <- ggplot(top_meals, aes(x = reorder_within(Anon_ID, Blocks, Meal), y = Blocks, fill = Meal)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  scale_x_reordered() +
  facet_wrap(~Meal, scales = "free", ncol = 3) +
  scale_fill_manual(values = c("Breakfast" = "#f1c40f", "Lunch" = "#e67e22", "Dinner" = "#2c3e50")) +
  labs(title = "Top Consumers by Meal Time",
       subtitle = "Who eats the most at each time of day? (Anonymized)",
       x = "", y = "Blocks Purchased") +
  theme_minimal()

ggsave("top_meal_consumers.png", p4, width = 12, height = 6)

print("Analysis complete. Generated: top_anonymous_participants.png, buyer_spend_distribution.png, top_meal_consumers.png")

