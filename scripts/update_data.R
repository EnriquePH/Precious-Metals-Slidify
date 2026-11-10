# Refresh data/metals.csv with the latest prices (run before rendering).
# Usage: Rscript scripts/update_data.R [years]
source("R/metals.R")
args <- commandArgs(trailingOnly = TRUE)
years <- if (length(args)) as.numeric(args[[1]]) else 5
df <- fetch_prices(years)
dir.create(dirname(DATA_FILE), showWarnings = FALSE)
utils::write.csv(df, DATA_FILE, row.names = FALSE)
cat(sprintf("%s: %d rows, %s to %s\n", DATA_FILE, nrow(df), min(df$date), max(df$date)))
