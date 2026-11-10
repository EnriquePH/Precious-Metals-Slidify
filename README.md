[![Publish slides](https://github.com/EnriquePH/Precious-Metals-Slidify/actions/workflows/publish.yml/badge.svg)](https://github.com/EnriquePH/Precious-Metals-Slidify/actions/workflows/publish.yml)
[![Slides](https://img.shields.io/badge/slides-GitHub%20Pages-1f77b4.svg)](https://enriqueph.github.io/Precious-Metals-Slidify/)
[![Made with Quarto](https://img.shields.io/badge/made%20with-Quarto-39729E.svg)](https://quarto.org/)
[![R >= 4.1](https://img.shields.io/badge/R-%3E%3D4.1-276DC3.svg?logo=r)](https://www.r-project.org/)
[![License: GPL v2](https://img.shields.io/badge/License-GPL%20v2-blue.svg)](LICENSE)

# Precious Metals Price Forecast — slides

Presentation of the [Precious-Metals-Prediction](https://github.com/EnriquePH/Precious-Metals-Prediction)
Shiny app, first made with slidify for the Coursera course *Developing Data Products*
(December 2015) and rebuilt in 2026 with Quarto and reveal.js.

**[See the slides](https://enriqueph.github.io/Precious-Metals-Slidify/)**

## What it shows

- Five years of daily prices of gold, silver, platinum and palladium (COMEX/NYMEX front-month
  futures from Yahoo Finance), in USD, EUR and GBP.
- A three-month (63 trading days) ARIMA forecast of each metal with `forecast::auto.arima()` on
  log prices, with 80 % and 95 % intervals.
- A back-test: each model is fitted without the last 63 days and compared with the naive
  forecast (tomorrow = today). For asset prices the naive forecast is very hard to beat, and the
  slides say so.
- Residual checks (Ljung–Box) and links.

GitHub Actions downloads new prices and republishes the slides on the first day of every month.

## Build it

Requirements: R (>= 4.1) with `quantmod`, `forecast`, `ggplot2`, `plotly`, `scales`, `knitr` and
`rmarkdown`, and [Quarto](https://quarto.org/) (>= 1.4).

```sh
make data      # download the latest prices to data/metals.csv
make render    # build the slides in _site/
make preview   # live preview
make lint      # lintr on R/ and scripts/
```

| Path | Content |
|---|---|
| `index.qmd` | the slides |
| `R/metals.R` | data download, ARIMA, back-test and plot style |
| `scripts/update_data.R` | refreshes `data/metals.csv` |
| `data/metals.csv` | prices used in the last build |
| `legacy/2015-slidify/` | the original slidify presentation, unchanged (also tag `slidify-2015`) |

The original data source, Oanda, no longer serves metal prices to `quantmod::getMetals()`.

Not investment advice.

## Author

Enrique Pérez Herrero · [eph.project1500@gmail.com](mailto:eph.project1500@gmail.com)
