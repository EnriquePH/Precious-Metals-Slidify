# Precious Metals slides (Quarto + reveal.js)
.PHONY: help data render preview publish lint clean

help:
	@echo "make data     download the latest prices to data/metals.csv"
	@echo "make render   build the slides in _site/"
	@echo "make preview  live preview in the browser"
	@echo "make publish  publish _site to GitHub Pages (gh-pages branch)"
	@echo "make lint     lintr on R/ and scripts/"
	@echo "make clean    remove generated files"

data:
	Rscript scripts/update_data.R

render:
	quarto render

preview:
	quarto preview

publish:
	quarto publish gh-pages --no-prompt

lint:
	Rscript -e 'lints <- c(lintr::lint_dir("R"), lintr::lint_dir("scripts")); print(lints); quit(status = length(lints) > 0)'

clean:
	rm -rf _site .quarto index_files
