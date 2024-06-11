.PHONY: all

all: build-index

build-index: build-index.py
	python3 build-index.py > README.md
