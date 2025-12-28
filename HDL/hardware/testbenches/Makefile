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
TB_SOF = tb_usb_sof_generator
TB_RESET = tb_usb_reset_controller
TB_DESCRIPTOR = tb_usb_descriptor_parser
TB_ARBITER = tb_usb_host_arbiter

# Default target
all: test_token test_transaction test_sof test_reset test_descriptor test_arbiter

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

# SOF Generator Test
test_sof: $(TB_SOF)
	@echo "Running SOF Generator test..."
	$(VVP) $(TB_SOF)

$(TB_SOF): $(TB_DIR)/$(TB_SOF).v $(USB_IF_DIR)/usb_sof_generator.v $(USB_IF_DIR)/usb_token_generator.v
	$(IVERILOG) $(IVFLAGS) -o $@ $^

# Reset Controller Test
test_reset: $(TB_RESET)
	@echo "Running Reset Controller test..."
	$(VVP) $(TB_RESET)

$(TB_RESET): $(TB_DIR)/$(TB_RESET).v $(USB_IF_DIR)/usb_reset_controller.v
	$(IVERILOG) $(IVFLAGS) -o $@ $^

# Descriptor Parser Test
test_descriptor: $(TB_DESCRIPTOR)
	@echo "Running Descriptor Parser test..."
	$(VVP) $(TB_DESCRIPTOR)

$(TB_DESCRIPTOR): $(TB_DIR)/$(TB_DESCRIPTOR).v $(USB_IF_DIR)/usb_descriptor_parser.v
	$(IVERILOG) $(IVFLAGS) -o $@ $^

# Host Arbiter Test
test_arbiter: $(TB_ARBITER)
	@echo "Running Host Arbiter test..."
	$(VVP) $(TB_ARBITER)

$(TB_ARBITER): $(TB_DIR)/$(TB_ARBITER).v $(USB_IF_DIR)/usb_host_arbiter.v
	$(IVERILOG) $(IVFLAGS) -o $@ $^

# View waveforms
wave_token:
	$(GTKWAVE) $(TB_TOKEN).vcd &

wave_transaction:
	$(GTKWAVE) $(TB_TRANSACTION).vcd &

wave_sof:
	$(GTKWAVE) $(TB_SOF).vcd &

wave_reset:
	$(GTKWAVE) $(TB_RESET).vcd &

wave_descriptor:
	$(GTKWAVE) $(TB_DESCRIPTOR).vcd &

wave_arbiter:
	$(GTKWAVE) $(TB_ARBITER).vcd &

# Lint all RTL files
lint:
	@echo "Linting USB interface modules..."
	@for file in $(USB_COMMON); do \
		echo "Checking $$file..."; \
		$(IVERILOG) $(IVFLAGS) -t null $$file 2>&1 | grep -v "warning: macro" || true; \
	done

# Clean
clean:
	rm -f $(TB_TOKEN) $(TB_TRANSACTION) $(TB_SOF) $(TB_RESET) $(TB_DESCRIPTOR) $(TB_ARBITER)
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
	@echo "  test_sof          - Run SOF generator test"
	@echo "  test_reset        - Run reset controller test"
	@echo "  test_descriptor   - Run descriptor parser test"
	@echo "  test_arbiter      - Run host arbiter test"
	@echo "  wave_token        - View token generator waveforms"
	@echo "  wave_transaction  - View transaction engine waveforms"
	@echo "  wave_sof          - View SOF generator waveforms"
	@echo "  wave_reset        - View reset controller waveforms"
	@echo "  wave_descriptor   - View descriptor parser waveforms"
	@echo "  wave_arbiter      - View host arbiter waveforms"
	@echo "  lint              - Check syntax of all RTL files"
	@echo "  clean             - Remove generated files"
	@echo "  help              - Show this help message"
	@echo ""
	@echo "Requirements:"
	@echo "  - Icarus Verilog (iverilog)"
	@echo "  - GTKWave (for waveform viewing)"

.PHONY: all test_token test_transaction test_sof test_reset test_descriptor test_arbiter \
        wave_token wave_transaction wave_sof wave_reset wave_descriptor wave_arbiter \
        lint clean help
