BATS ?= bats
SCRIPT = bin/bashbudget
TEST_DIR = test

.PHONY: all test lint check

all: check

check: lint test

test:
	@echo "Running tests with Bats..."
	@$(BATS) $(TEST_DIR)/test_*

lint:
	@echo "Running shellcheck on script..."
	@shellcheck $(SCRIPT)
