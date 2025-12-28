.PHONY: all synth synth-fast synth-max pnr bitstream flash clean validate help
.SILENT: help

# Detect number of CPU cores
NPROC := $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
JOBS ?= $(NPROC)

# Directories
HDL_ROOT := $(shell pwd)
RTL_DIR := $(HDL_ROOT)/hardware/rtl
CONSTRAINTS_DIR := $(HDL_ROOT)/hardware/constraints
BUILD_DIR := $(HDL_ROOT)/tools/build
TOOLS_DIR := $(HDL_ROOT)/tools

# Build targets
TOP_MODULE := top
SYNTH_JSON := $(BUILD_DIR)/$(TOP_MODULE)_synth.json
ROUTED_JSON := $(BUILD_DIR)/$(TOP_MODULE)_routed.json
BITSTREAM := $(BUILD_DIR)/$(TOP_MODULE).bit
CONSTRAINT_FILE := $(CONSTRAINTS_DIR)/cynthion_pins.lpf

# Synthesis scripts
SYNTH_SCRIPT := $(BUILD_DIR)/synth.ys
SYNTH_FAST_SCRIPT := $(BUILD_DIR)/synth_fast.ys
SYNTH_MAX_SCRIPT := $(BUILD_DIR)/synth_max.ys

# Find all Verilog source files
VERILOG_SRCS := $(shell find $(RTL_DIR) -name "*.v")

# Colors
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[0;33m
NC := \033[0m

help:
	@echo "$(CYAN)HurricaneFPGA HDL Build System$(NC)"
	@echo ""
	@echo "$(GREEN)Targets:$(NC)"
	@echo "  all        - BALANCED build (good speed + quality)"
	@echo "  fast       - Quick build (minimal optimization)"
	@echo "  max        - Maximum quality (very slow)"
	@echo "  synth      - Run Yosys synthesis (balanced)"
	@echo "  synth-fast - Run Yosys synthesis (quick)"
	@echo "  synth-max  - Run Yosys synthesis (maximum optimization)"
	@echo "  pnr        - Run place and route (requires synth)"
	@echo "  bitstream  - Generate final bitstream (requires pnr)"
	@echo "  flash      - Flash bitstream to device"
	@echo "  validate   - Validate Verilog files"
	@echo "  clean      - Remove build artifacts"
	@echo ""
	@echo "$(GREEN)Build Modes:$(NC)"
	@echo "  $(YELLOW)fast$(NC)     ~30s synth  | Good for iteration"
	@echo "  $(YELLOW)all$(NC)      ~1-2min     | RECOMMENDED - good balance"
	@echo "  $(YELLOW)max$(NC)      ~3-5min     | Best quality, very slow"
	@echo ""
	@echo "$(GREEN)Options:$(NC)"
	@echo "  JOBS=N     - Use N parallel jobs for PnR (default: $(NPROC))"
	@echo ""
	@echo "$(GREEN)Usage:$(NC)"
	@echo "  make all           # Recommended - balanced build"
	@echo "  make fast          # Quick iteration"
	@echo "  make max           # Production quality"
	@echo "  make clean fast    # Clean quick rebuild"

all: validate synth pnr bitstream
	@echo "$(GREEN)✓ Complete BALANCED build finished!$(NC)"
	@echo "  Bitstream: $(BITSTREAM)"

fast: validate synth-fast pnr bitstream
	@echo "$(GREEN)✓ Fast build finished!$(NC)"
	@echo "  Bitstream: $(BITSTREAM)"

max: validate synth-max pnr bitstream
	@echo "$(GREEN)✓ Maximum quality build finished!$(NC)"
	@echo "  Bitstream: $(BITSTREAM)"

validate:
	@echo "$(CYAN)[1/4] Validating HDL files...$(NC)"
	@$(TOOLS_DIR)/validate_hdl.sh -v

$(SYNTH_JSON): $(VERILOG_SRCS) $(SYNTH_SCRIPT)
	@echo "$(CYAN)[2/4] Running BALANCED synthesis...$(NC)"
	@mkdir -p $(BUILD_DIR)/logs
	@yosys -q -l $(BUILD_DIR)/logs/synthesis.log $(SYNTH_SCRIPT)
	@echo "$(GREEN)✓ Synthesis complete$(NC)"

synth: validate $(SYNTH_JSON)

synth-fast: validate
	@echo "$(CYAN)[2/4] Running FAST synthesis (minimal optimizations)...$(NC)"
	@mkdir -p $(BUILD_DIR)/logs
	@yosys -q -l $(BUILD_DIR)/logs/synthesis_fast.log $(SYNTH_FAST_SCRIPT)
	@echo "$(GREEN)✓ Fast synthesis complete$(NC)"

synth-max: validate
	@echo "$(CYAN)[2/4] Running MAXIMUM optimization synthesis...$(NC)"
	@echo "$(YELLOW)      WARNING: This will take 3-5 minutes$(NC)"
	@mkdir -p $(BUILD_DIR)/logs
	@yosys -q -l $(BUILD_DIR)/logs/synthesis_max.log $(SYNTH_MAX_SCRIPT)
	@echo "$(GREEN)✓ Maximum optimization complete$(NC)"

$(ROUTED_JSON): $(SYNTH_JSON) $(CONSTRAINT_FILE)
	@echo "$(CYAN)[3/4] Running place-and-route with $(JOBS) threads...$(NC)"
	@nextpnr-ecp5 \
		--12k \
		--package CABGA256 \
		--json $(SYNTH_JSON) \
		--lpf $(CONSTRAINT_FILE) \
		--textcfg $(BUILD_DIR)/$(TOP_MODULE)_out.config \
		--write $(ROUTED_JSON) \
		--log $(BUILD_DIR)/logs/pnr.log \
		--threads $(JOBS) \
		--parallel-refine \
		--quiet
	@echo "$(GREEN)✓ Place-and-route complete$(NC)"

pnr: $(ROUTED_JSON)

$(BITSTREAM): $(ROUTED_JSON)
	@echo "$(CYAN)[4/4] Generating bitstream...$(NC)"
	@ecppack --compress \
		--input $(BUILD_DIR)/$(TOP_MODULE)_out.config \
		--bit $(BITSTREAM) \
		--svf $(BUILD_DIR)/$(TOP_MODULE).svf
	@echo "$(GREEN)✓ Bitstream ready: $(BITSTREAM)$(NC)"

bitstream: $(BITSTREAM)

flash: $(BITSTREAM)
	@echo "$(YELLOW)Flashing to device...$(NC)"
	openFPGALoader --board cynthion $(BITSTREAM)
	@echo "$(GREEN)✓ Flashed successfully!$(NC)"

clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	rm -rf $(BUILD_DIR)/*.json $(BUILD_DIR)/*.bit $(BUILD_DIR)/*.svf $(BUILD_DIR)/*.config
	rm -rf $(BUILD_DIR)/logs/*
	@echo "$(GREEN)✓ Clean complete$(NC)"

# Incremental build support - only rebuild if sources change
.PRECIOUS: $(SYNTH_JSON) $(ROUTED_JSON)
