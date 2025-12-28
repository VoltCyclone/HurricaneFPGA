# Makefile for HurricaneFPGA USB Host Components
# Supports Icarus Verilog simulation

# Directories
RTL_DIR = ../rtl
USB_IF_DIR = $(RTL_DIR)/usb_interface
USB_ENGINE_DIR = $(RTL_DIR)/usb_engines
TB_DIR = .

# Icarus Verilog compiler
IVERILOG = iverilog
VVP = vvp
GTKWAVE = gtkwave

# Compiler flags
IVFLAGS = -g2012 -Wall

# Common RTL files
USB_COMMON = \
	$(USB_IF_DIR)/usb_token_generator.v \
	$(USB_IF_DIR)/usb_reset_controller.v \
	$(USB_IF_DIR)/usb_sof_generator.v \
	$(USB_IF_DIR)/usb_descriptor_parser.v \
	$(USB_IF_DIR)/usb_transaction_engine.v

# Testbenches
TB_TOKEN = tb_usb_token_generator
TB_TRANSACTION = tb_usb_transaction_engine

# Default target
all: test_token test_transaction

# Token Generator Test
test_token: $(TB_TOKEN)
	@echo "Running Token Generator test..."
	$(VVP) $(TB_TOKEN)

$(TB_TOKEN): $(TB_DIR)/$(TB_TOKEN).v $(USB_IF_DIR)/usb_token_generator.v
	$(IVERILOG) $(IVFLAGS) -o $@ $^

# Transaction Engine Test
test_transaction: $(TB_TRANSACTION)
	@echo "Running Transaction Engine test..."
	$(VVP) $(TB_TRANSACTION)

$(TB_TRANSACTION): $(TB_DIR)/$(TB_TRANSACTION).v $(USB_IF_DIR)/usb_transaction_engine.v $(USB_IF_DIR)/usb_token_generator.v
	$(IVERILOG) $(IVFLAGS) -o $@ $^

# View waveforms
wave_token:
	$(GTKWAVE) $(TB_TOKEN).vcd &

wave_transaction:
	$(GTKWAVE) $(TB_TRANSACTION).vcd &

# Lint all RTL files
lint:
	@echo "Linting USB interface modules..."
	@for file in $(USB_COMMON); do \
		echo "Checking $$file..."; \
		$(IVERILOG) $(IVFLAGS) -t null $$file 2>&1 | grep -v "warning: macro" || true; \
	done

# Clean
clean:
	rm -f $(TB_TOKEN) $(TB_TRANSACTION)
	rm -f *.vcd
	rm -f *.lxt

# Help
help:
	@echo "HurricaneFPGA USB Host Component Testbenches"
	@echo ""
	@echo "Targets:"
	@echo "  all               - Run all tests"
	@echo "  test_token        - Run token generator test"
	@echo "  test_transaction  - Run transaction engine test"
	@echo "  wave_token        - View token generator waveforms"
	@echo "  wave_transaction  - View transaction engine waveforms"
	@echo "  lint              - Check syntax of all RTL files"
	@echo "  clean             - Remove generated files"
	@echo "  help              - Show this help message"
	@echo ""
	@echo "Requirements:"
	@echo "  - Icarus Verilog (iverilog)"
	@echo "  - GTKWave (for waveform viewing)"

.PHONY: all test_token test_transaction wave_token wave_transaction lint clean help
