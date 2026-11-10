# Data, models and plot style for the Precious Metals slides.
#
# Prices are the daily settlement of the COMEX/NYMEX front-month futures from
# Yahoo Finance (Oanda, used by the 2015 version, no longer serves metal
# prices to quantmod). Futures track spot closely enough for this purpose.

METALS <- c(
  Gold = "GC=F",
  Silver = "SI=F",
  Platinum = "PL=F",
  Palladium = "PA=F"
)

FX <- c(EUR = "EURUSD=X", GBP = "GBPUSD=X")

DATA_FILE <- "data/metals.csv"

# Trading days ahead: about three months.
HORIZON <- 63

close_series <- function(symbol, from) {
  x <- suppressWarnings(
    quantmod::getSymbols(symbol, src = "yahoo", from = from, auto.assign = FALSE)
  )
  x <- zoo::na.locf(quantmod::Cl(x), na.rm = TRUE)
  stats::setNames(x, symbol)
}

#' Download daily prices (USD per troy ounce) and convert them to EUR and GBP.
#'
#' @param years Number of years of history.
#' @return Long data frame: date, metal, usd, eur, gbp.
fetch_prices <- function(years = 5) {
  from <- Sys.Date() - round(365.25 * years)
  fx <- do.call(merge, lapply(FX, close_series, from = from))
  out <- lapply(names(METALS), function(metal) {
    p <- close_series(METALS[[metal]], from = from)
    # FX columns 2 and 3: EUR, GBP (merge() renames them)
    m <- zoo::na.locf(merge(p, fx), na.rm = TRUE)[zoo::index(p)]
    m <- m[stats::complete.cases(m)]
    usd <- as.numeric(m[, 1])
    data.frame(
      date = zoo::index(m),
      metal = metal,
      usd = usd,
      eur = usd / as.numeric(m[, 2]),
      gbp = usd / as.numeric(m[, 3])
    )
  })
  do.call(rbind, out)
}

#' Read the saved prices (see scripts/update_data.R).
load_prices <- function(path = DATA_FILE) {
  df <- utils::read.csv(path, stringsAsFactors = FALSE)
  df$date <- as.Date(df$date)
  df$metal <- factor(df$metal, levels = names(METALS))
  df
}

next_trading_days <- function(last, n) {
  d <- seq(last + 1, by = "day", length.out = ceiling(n * 1.6) + 10)
  d <- d[!format(d, "%u") %in% c("6", "7")]
  d[seq_len(n)]
}

#' ARIMA on log prices (lambda = 0), so bands stay positive and widen with the
#' price level.
fit_arima <- function(y) {
  forecast::auto.arima(y, lambda = 0, stepwise = TRUE, approximation = FALSE)
}

#' Forecast one metal: model, and a data frame ready to plot.
forecast_metal <- function(df, metal, h = HORIZON, currency = "usd") {
  s <- df[df$metal == metal, ]
  s <- s[order(s$date), ]
  fit <- fit_arima(stats::ts(s[[currency]]))
  fc <- forecast::forecast(fit, h = h, level = c(80, 95))
  future <- data.frame(
    date = next_trading_days(max(s$date), h),
    mean = as.numeric(fc$mean),
    lo80 = as.numeric(fc$lower[, 1]), hi80 = as.numeric(fc$upper[, 1]),
    lo95 = as.numeric(fc$lower[, 2]), hi95 = as.numeric(fc$upper[, 2])
  )
  list(fit = fit, history = s, future = future)
}

#' Hold out the last h days, fit on the rest and compare with the naive
#' forecast (tomorrow = today), the usual benchmark for asset prices.
backtest <- function(df, h = HORIZON, currency = "usd") {
  rows <- lapply(levels(df$metal), function(metal) {
    y <- df[df$metal == metal, ]
    y <- y[order(y$date), ][[currency]]
    n <- length(y)
    train <- stats::ts(y[seq_len(n - h)])
    test <- y[(n - h + 1):n]
    fit <- fit_arima(train)
    arima <- as.numeric(forecast::forecast(fit, h = h)$mean)
    naive <- rep(utils::tail(as.numeric(train), 1), h)
    err <- function(f) c(rmse = sqrt(mean((test - f)^2)), mape = 100 * mean(abs(test - f) / test))
    a <- err(arima)
    b <- err(naive)
    data.frame(
      Metal = metal,
      Model = as.character(fit),
      `RMSE ARIMA` = a[["rmse"]], `RMSE naive` = b[["rmse"]],
      `MAPE ARIMA (%)` = a[["mape"]], `MAPE naive (%)` = b[["mape"]],
      check.names = FALSE
    )
  })
  do.call(rbind, rows)
}

INK <- "#1f2328"
MODEL <- "#1f77b4"

#' Shared look (same idea as theme_metals() in Precious-Metals-Prediction):
#' dark ink for history, one blue hue for the model, two steps of it for the
#' 80 % and 95 % bands.
theme_metals <- function(base_size = 14) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      plot.title.position = "plot",
      legend.position = "bottom",
      strip.text = ggplot2::element_text(face = "bold", hjust = 0)
    )
}

plot_forecast <- function(fm, metal, days_shown = 260, unit = "USD / oz") {
  hist <- utils::tail(fm$history, days_shown)
  f <- fm$future
  ggplot2::ggplot() +
    ggplot2::geom_ribbon(
      data = f, ggplot2::aes(date, ymin = lo95, ymax = hi95, fill = "95 % interval")
    ) +
    ggplot2::geom_ribbon(
      data = f, ggplot2::aes(date, ymin = lo80, ymax = hi80, fill = "80 % interval")
    ) +
    ggplot2::geom_line(data = hist, ggplot2::aes(date, usd, colour = "Observed"), linewidth = 0.6) +
    ggplot2::geom_line(data = f, ggplot2::aes(date, mean, colour = "Forecast"), linewidth = 0.9) +
    ggplot2::scale_fill_manual(
      NULL,
      values = c("80 % interval" = grDevices::adjustcolor(MODEL, 0.45),
                 "95 % interval" = grDevices::adjustcolor(MODEL, 0.18))
    ) +
    ggplot2::scale_colour_manual(NULL, values = c(Observed = INK, Forecast = MODEL)) +
    ggplot2::scale_y_continuous(labels = scales::label_comma()) +
    ggplot2::labs(
      title = sprintf("%s: %s", metal, as.character(fm$fit)),
      x = NULL, y = unit
    ) +
    theme_metals()
}
