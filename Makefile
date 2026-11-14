.PHONY: lint test build check-build clean ci

lint:
	python3 scripts/check-shell.py

test:
	bats tests/*.bats

build:
	./examples/build-standalone.sh

check-build: build
	git diff --exit-code -- unleash-standalone.sh

clean:
	rm -f unleash-standalone.sh

ci: lint test check-build
