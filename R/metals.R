# Data, models and plot style for the Precious Metals slides.
#
# Prices are the daily settlement of the COMEX/NYMEX front-month futures from
# Yahoo Finance (Oanda, used by the 2015 version, no longer serves metal
# prices to quantmod). Futures track spot closely enough for this purpose.
#
# Documented with roxygen2 comments (#'). The project is not an R package, so
# no man/ pages are generated; the comments document parameters and results
# for whoever reads or reuses the code.

#' Yahoo Finance symbols of the metals
#'
#' Front-month futures, priced in USD per troy ounce: gold and silver on
#' COMEX, platinum and palladium on NYMEX.
#'
#' @format Named character vector: display name -> Yahoo Finance symbol.
METALS <- c(
  Gold = "GC=F",
  Silver = "SI=F",
  Platinum = "PL=F",
  Palladium = "PA=F"
)

#' Yahoo Finance symbols of the exchange rates
#'
#' US dollars per unit of each currency, used to convert the USD prices.
#'
#' @format Named character vector: ISO currency code -> Yahoo Finance symbol.
FX <- c(EUR = "EURUSD=X", GBP = "GBPUSD=X")

#' Path of the saved prices, relative to the project root
#'
#' Written by `scripts/update_data.R`, read by [load_prices()].
DATA_FILE <- "data/metals.csv"

#' Forecast horizon in trading days (about three months)
HORIZON <- 63

#' Daily closing prices of one Yahoo Finance symbol
#'
#' Missing closes (exchange holidays, gaps in the feed) are filled with the
#' previous one, and leading gaps are dropped.
#'
#' @param symbol Yahoo Finance symbol, e.g. `"GC=F"`.
#' @param from First date to download, a `Date`.
#' @return A one-column `xts` series named after `symbol`.
close_series <- function(symbol, from) {
  x <- suppressWarnings(
    quantmod::getSymbols(symbol, src = "yahoo", from = from, auto.assign = FALSE)
  )
  x <- zoo::na.locf(quantmod::Cl(x), na.rm = TRUE)
  stats::setNames(x, symbol)
}

#' Download the metal prices and convert them to EUR and GBP
#'
#' For each metal in [METALS], downloads the daily closes in USD per troy
#' ounce and divides them by the exchange rate of the same day ([FX]; the
#' last quoted rate when a day has none). Only days with a metal price are
#' kept.
#'
#' @param years Number of years of history to download.
#' @return A long data frame with one row per metal and trading day and the
#'   columns `date` (`Date`), `metal` (character), `usd`, `eur` and `gbp`
#'   (price per troy ounce in each currency).
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

#' Read the saved prices
#'
#' @param path CSV written by `scripts/update_data.R` (the result of
#'   [fetch_prices()]).
#' @return The same long data frame as [fetch_prices()], with `date` as
#'   `Date` and `metal` as a factor in the order of [METALS].
load_prices <- function(path = DATA_FILE) {
  df <- utils::read.csv(path, stringsAsFactors = FALSE)
  df$date <- as.Date(df$date)
  df$metal <- factor(df$metal, levels = names(METALS))
  df
}

#' Next trading days after a date
#'
#' Prices exist only from Monday to Friday, so the forecast horizon is dated
#' with weekdays. Exchange holidays are not taken into account.
#'
#' @param last Last observed date, a `Date`.
#' @param n Number of days wanted.
#' @return A `Date` vector of length `n`, all of them weekdays after `last`.
next_trading_days <- function(last, n) {
  d <- seq(last + 1, by = "day", length.out = ceiling(n * 1.6) + 10)
  d <- d[!format(d, "%u") %in% c("6", "7")]
  d[seq_len(n)]
}

#' Fit an ARIMA model to a price series
#'
#' Uses [forecast::auto.arima()] on the logarithm of the price (Box-Cox
#' `lambda = 0`), so the forecast intervals stay positive and widen in
#' proportion to the price level.
#'
#' @param y Price series, a `ts` object or numeric vector.
#' @return An `Arima` model (also of class `forecast_ARIMA`).
fit_arima <- function(y) {
  forecast::auto.arima(y, lambda = 0, stepwise = TRUE, approximation = FALSE)
}

#' Forecast the price of one metal
#'
#' @param df Long price data frame, as returned by [load_prices()].
#' @param metal Metal name, one of `names(METALS)`.
#' @param h Horizon in trading days.
#' @param currency Price column to model: `"usd"`, `"eur"` or `"gbp"`.
#' @return A list with
#'   * `fit`: the model from [fit_arima()];
#'   * `history`: the rows of `df` for that metal, sorted by date;
#'   * `future`: a data frame with the forecast dates (trading days), the
#'     mean forecast (`mean`) and the 80 % and 95 % intervals (`lo80`,
#'     `hi80`, `lo95`, `hi95`).
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
  list(fit = fit, history = s, future = future, currency = currency)
}

#' Forecast errors against the observed prices
#'
#' @param observed Observed prices.
#' @param predicted Forecast prices, same length as `observed`.
#' @return A named numeric vector: `rmse` (root mean squared error, in price
#'   units) and `mape` (mean absolute percentage error, in %).
forecast_errors <- function(observed, predicted) {
  c(
    rmse = sqrt(mean((observed - predicted)^2)),
    mape = 100 * mean(abs(observed - predicted) / observed)
  )
}

#' Back-test ARIMA against the naive forecast
#'
#' For each metal, the last `h` days are held out, the model is fitted on the
#' rest with [fit_arima()] and its forecast is compared with what really
#' happened, and with the naive forecast (every future price equal to the last
#' known one), the usual benchmark for asset prices.
#'
#' @param df Long price data frame, as returned by [load_prices()].
#' @param h Number of days held out (and forecast).
#' @param currency Price column to test: `"usd"`, `"eur"` or `"gbp"`.
#' @return A data frame with one row per metal: `Metal`, `Model` (ARIMA
#'   orders), and RMSE and MAPE of the ARIMA and naive forecasts.
backtest <- function(df, h = HORIZON, currency = "usd") {
  rows <- lapply(levels(df$metal), function(metal) {
    y <- df[df$metal == metal, ]
    y <- y[order(y$date), ][[currency]]
    n <- length(y)
    train <- stats::ts(y[seq_len(n - h)])
    test <- y[(n - h + 1):n]
    fit <- fit_arima(train)
    a <- forecast_errors(test, as.numeric(forecast::forecast(fit, h = h)$mean))
    b <- forecast_errors(test, rep(utils::tail(as.numeric(train), 1), h))
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

#' Colours of the charts
#'
#' `INK` for observed prices, `MODEL` for the forecast and, lighter, its
#' intervals.
INK <- "#1f2328"

#' @rdname INK
MODEL <- "#1f77b4"

#' Common ggplot2 theme of the slides
#'
#' Same idea as `theme_metals()` in the Precious-Metals-Prediction app:
#' minimal grid, title aligned with the plot, legend at the bottom and bold
#' facet labels.
#'
#' @param base_size Base font size, passed to [ggplot2::theme_minimal()].
#' @return A ggplot2 `theme` object.
theme_metals <- function(base_size = 14) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      plot.title.position = "plot",
      legend.position = "bottom",
      strip.text = ggplot2::element_text(face = "bold", hjust = 0)
    )
}

#' Plot the recent history and the forecast of one metal
#'
#' Observed prices in [INK], the mean forecast in [MODEL] and the 80 % and
#' 95 % intervals as two steps of the same blue (darker = 80 %).
#'
#' @param fm Forecast, as returned by [forecast_metal()].
#' @param metal Metal name, used in the title.
#' @param days_shown Number of past trading days drawn before the forecast.
#' @param unit Label of the y axis.
#' @return A `ggplot` object.
plot_forecast <- function(fm, metal, days_shown = 260, unit = "USD / oz") {
  hist <- utils::tail(fm$history, days_shown)
  hist$price <- hist[[fm$currency]]
  f <- fm$future
  ggplot2::ggplot() +
    ggplot2::geom_ribbon(
      data = f, ggplot2::aes(date, ymin = lo95, ymax = hi95, fill = "95 % interval")
    ) +
    ggplot2::geom_ribbon(
      data = f, ggplot2::aes(date, ymin = lo80, ymax = hi80, fill = "80 % interval")
    ) +
    ggplot2::geom_line(
      data = hist, ggplot2::aes(date, price, colour = "Observed"), linewidth = 0.6
    ) +
    ggplot2::geom_line(
      data = f, ggplot2::aes(date, mean, colour = "Forecast"), linewidth = 0.9
    ) +
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
