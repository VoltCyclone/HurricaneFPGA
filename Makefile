.PHONY: help build build-fast deploy clean clean-cache clean-all rebuild rebuild-fast run-python run-rust test test-local test-rust test-python test-docker-rust test-docker-python docker-shell

# Default Docker image name
IMAGE_NAME ?= amaranth-cynthion
BUILD_DIR := ./build

# Docker BuildKit settings for better caching
export DOCKER_BUILDKIT=1
export BUILDKIT_PROGRESS=plain

# Colors for output
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "$(CYAN)HurricaneFPGA Build System$(NC)"
	@echo ""
	@echo "$(GREEN)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Usage examples:$(NC)"
	@echo "  make build          # Build Docker image and extract artifacts"
	@echo "  make build-fast     # Fast rebuild using existing cache"
	@echo "  make test           # Run all tests in Docker container"
	@echo "  make test-local     # Run all tests locally"
	@echo "  make rebuild        # Clean everything and rebuild from scratch"
	@echo "  make rebuild-fast   # Clean artifacts but keep cache"
	@echo "  make deploy         # Extract artifacts from existing image"
	@echo "  make run-rust       # Run the Rust CLI tool"

build: ## Build Docker image and extract artifacts
	@echo "$(CYAN)Building Docker image with BuildKit caching...$(NC)"
	docker buildx build \
		--load \
		--cache-from=type=local,src=/tmp/docker-cache-$(IMAGE_NAME) \
		--cache-to=type=local,dest=/tmp/docker-cache-$(IMAGE_NAME),mode=max \
		-t $(IMAGE_NAME) \
		.
	@echo "$(GREEN)Build complete!$(NC)"
	@$(MAKE) deploy

build-fast: ## Build Docker image using existing cache (skip cache export)
	@echo "$(CYAN)Fast building Docker image using cache...$(NC)"
	docker buildx build \
		--load \
		--cache-from=type=local,src=/tmp/docker-cache-$(IMAGE_NAME) \
		-t $(IMAGE_NAME) \
		.
	@echo "$(GREEN)Fast build complete!$(NC)"
	@$(MAKE) deploy

deploy: ## Extract build artifacts from Docker container
	@echo "$(CYAN)Deploying build artifacts...$(NC)"
	./deploy.sh $(IMAGE_NAME)
	@echo "$(GREEN)Deployment complete!$(NC)"

clean: ## Remove build artifacts (keeps Docker image)
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	rm -rf $(BUILD_DIR)/binaries
	rm -f $(BUILD_DIR)/build-info.txt
	@echo "$(GREEN)Cleaned!$(NC)"

clean-all: clean ## Remove build artifacts AND Docker image
	@echo "$(YELLOW)Removing Docker image...$(NC)"
	docker rmi $(IMAGE_NAME) 2>/dev/null || true
	@echo "$(GREEN)Deep clean complete!$(NC)"

clean-cache: ## Remove Docker build cache
	@echo "$(YELLOW)Removing Docker build cache...$(NC)"
	rm -rf /tmp/docker-cache-$(IMAGE_NAME)
	@echo "$(GREEN)Cache cleaned!$(NC)"

rebuild: clean-all clean-cache build ## Clean everything and rebuild from scratch

rebuild-fast: clean build-fast ## Clean artifacts but keep cache and rebuild

run-python: ## Run the Python gateware builder (legacy)
	@echo "$(CYAN)Running Python gateware builder...$(NC)"
	docker run --rm -it \
		--device=/dev/bus/usb \
		-v $(PWD):/work \
		$(IMAGE_NAME) \
		python legacy/src/flash_fpga.py

run-rust: deploy ## Run the Rust CLI tool (requires deploy first)
	@echo "$(CYAN)Running Rust CLI...$(NC)"
	@if [ -f $(BUILD_DIR)/binaries/hurricanefpga ]; then \
		$(BUILD_DIR)/binaries/hurricanefpga --help; \
	else \
		echo "$(RED)Error: Binary not found. Run 'make build' first.$(NC)"; \
		exit 1; \
	fi

test: ## Run all tests inside Docker container
	@echo "$(CYAN)Running tests in Docker container...$(NC)"
	@if ! docker image inspect $(IMAGE_NAME) > /dev/null 2>&1; then \
		echo "$(YELLOW)Docker image not found. Building...$(NC)"; \
		$(MAKE) build; \
	fi
	docker run --rm -it \
		-v $(PWD):/work \
		-w /work \
		$(IMAGE_NAME) \
		bash -c "cd firmware/samd51_hid_injector && cargo test --lib && cd /work && python3 tools/test_descriptor_unit.py && python3 tools/test_injection_unit.py"
	@echo "$(GREEN)All tests passed!$(NC)"

test-local: ## Run all tests locally (without Docker)
	@echo "$(CYAN)Running local tests...$(NC)"
	./run_tests.sh

test-rust: ## Run Rust firmware tests only
	@echo "$(CYAN)Running Rust tests...$(NC)"
	cd firmware/samd51_hid_injector && cargo test --lib

test-python: ## Run Python unit tests only
	@echo "$(CYAN)Running Python tests...$(NC)"
	python3 tools/test_descriptor_unit.py
	python3 tools/test_injection_unit.py

test-docker-rust: ## Run Rust tests in Docker container
	@echo "$(CYAN)Running Rust tests in Docker...$(NC)"
	docker run --rm -it \
		-v $(PWD):/work \
		-w /work/firmware/samd51_hid_injector \
		$(IMAGE_NAME) \
		cargo test --lib

test-docker-python: ## Run Python tests in Docker container
	@echo "$(CYAN)Running Python tests in Docker...$(NC)"
	docker run --rm -it \
		-v $(PWD):/work \
		-w /work \
		$(IMAGE_NAME) \
		bash -c "python3 tools/test_descriptor_unit.py && python3 tools/test_injection_unit.py"

test-coverage: ## Run tests with coverage (Rust only)
	@echo "$(CYAN)Running tests with coverage...$(NC)"
	cd firmware/samd51_hid_injector && cargo tarpaulin --out Html --output-dir target/coverage

docker-shell: ## Open a shell inside the Docker container
	@echo "$(CYAN)Opening Docker shell...$(NC)"
	docker run --rm -it \
		--device=/dev/bus/usb \
		-v $(PWD):/work \
		$(IMAGE_NAME) \
		/bin/bash

flash-hdl: compile-hdl ## Flash the HDL implementation to Cynthion
	@echo "$(CYAN)Flashing HDL bitstream...$(NC)"
	@if [ -f HDL/tools/build/top.bit ]; then \
		cd HDL/tools && ./flash_cynthion.sh -b build/top.bit; \
	else \
		echo "$(RED)Error: Bitstream not found. Compilation may have failed.$(NC)"; \
		exit 1; \
	fi

flash-hdl-fast: compile-hdl-fast ## Fast compile and flash HDL
	@echo "$(CYAN)Flashing HDL bitstream...$(NC)"
	@if [ -f HDL/tools/build/top.bit ]; then \
		cd HDL/tools && ./flash_cynthion.sh -b build/top.bit; \
	else \
		echo "$(RED)Error: Bitstream not found. Compilation may have failed.$(NC)"; \
		exit 1; \
	fi

hdl-clean: ## Clean HDL build artifacts
	@echo "$(YELLOW)Cleaning HDL build...$(NC)"
	cd HDL && $(MAKE) clean

flash-samd51: ## Flash the SAMD51 firmware to Cynthion
	@echo "$(CYAN)Flashing SAMD51 firmware...$(NC)"
	@if [ ! -f $(BUILD_DIR)/firmware/samd51_hid_injector ]; then \
		echo "$(YELLOW)Firmware not found, deploying from Docker image...$(NC)"; \
		$(MAKE) deploy; \
	fi
	@if [ -f $(BUILD_DIR)/firmware/samd51_hid_injector ]; then \
		if command -v dfu-util >/dev/null 2>&1; then \
			echo "$(YELLOW)Put Cynthion into DFU mode (hold PROGRAM button, press RESET)$(NC)"; \
			read -p "Press Enter when ready..." _; \
			dfu-util -d 1d50:615c -a 0 -D $(BUILD_DIR)/firmware/samd51_hid_injector; \
			echo "$(GREEN)SAMD51 firmware flashed successfully!$(NC)"; \
		else \
			echo "$(RED)Error: dfu-util not found. Install it with: brew install dfu-util$(NC)"; \
			exit 1; \
		fi; \
	else \
		echo "$(RED)Error: Firmware binary not found. Run 'make build' first.$(NC)"; \
		exit 1; \
	fi

compile-hdl: ## Compile HDL bitstream (balanced optimization)
	@echo "$(CYAN)Compiling HDL bitstream...$(NC)"
	cd HDL && $(MAKE) all

compile-hdl-fast: ## Compile HDL bitstream (fast, for iteration)
	@echo "$(CYAN)Compiling HDL bitstream (FAST mode)...$(NC)"
	cd HDL && $(MAKE) fast

compile-hdl-max: ## Compile HDL bitstream (maximum optimization, slow)
	@echo "$(CYAN)Compiling HDL bitstream (MAX optimization)...$(NC)"
	cd HDL && $(MAKE) max

validate-hdl: ## Validate HDL before building
	@echo "$(CYAN)Validating HDL...$(NC)"
	cd HDL/tools && ./validate_hdl.sh

info: ## Show build information
	@echo "$(CYAN)Build Information:$(NC)"
	@if [ -f $(BUILD_DIR)/build-info.txt ]; then \
		cat $(BUILD_DIR)/build-info.txt; \
	else \
		echo "$(YELLOW)No build info found. Run 'make build' first.$(NC)"; \
	fi
	@echo ""
	@echo "$(CYAN)Available binaries:$(NC)"
	@if [ -d $(BUILD_DIR)/binaries ]; then \
		ls -lh $(BUILD_DIR)/binaries/; \
	else \
		echo "$(YELLOW)No binaries found. Run 'make build' first.$(NC)"; \
	fi
	@echo ""
	@echo "$(CYAN)Available firmware:$(NC)"
	@if [ -d $(BUILD_DIR)/firmware ]; then \
		ls -lh $(BUILD_DIR)/firmware/; \
	else \
		echo "$(YELLOW)No firmware found. Run 'make build' first.$(NC)"; \
	fi

.DEFAULT_GOAL := help
