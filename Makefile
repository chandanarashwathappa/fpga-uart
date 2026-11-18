# fpga-uart: simulation with Icarus Verilog
#
#   make sim                 run every testbench whose files exist
#   make test_uart_tx        run one testbench
#   make wave TEST=uart_tx   open that test's waveform in GTKWave
#   make clean               delete build output
#
# Testbench rules (CI depends on these):
#   - top module is named tb_<test>, e.g. tb_uart_tx
#   - on success it prints a line starting with "PASS"
#   - on any mismatch it prints a line containing "FAIL"
#   - for waveforms: $dumpfile("tb_<test>.vcd"); $dumpvars(0, tb_<test>);

IVERILOG ?= iverilog
VVP      ?= vvp
GTKWAVE  ?= gtkwave
IVFLAGS  := -g2012 -Wall
BUILD    := build

TESTS := uart_tx uart_rx loopback spi

SRC_uart_tx  := rtl/uart_tx.sv tb/tb_uart_tx.sv
SRC_uart_rx  := rtl/uart_rx.sv tb/tb_uart_rx.sv
SRC_loopback := rtl/uart_tx.sv rtl/uart_rx.sv tb/tb_loopback.sv
SRC_spi      := rtl/spi_master.sv tb/tb_spi.sv

# A test is "available" once all of its source files exist.
missing   = $(filter-out $(wildcard $(SRC_$(1))),$(SRC_$(1)))
AVAILABLE := $(foreach t,$(TESTS),$(if $(call missing,$(t)),,$(t)))
SKIPPED   := $(filter-out $(AVAILABLE),$(TESTS))

.PHONY: sim wave clean

sim: $(addprefix test_,$(AVAILABLE))
	@echo "----------------------------------------"
	@echo "Ran:     $(if $(AVAILABLE),$(AVAILABLE),(none yet))"
	@echo "Skipped: $(if $(SKIPPED),$(SKIPPED) (files not written yet),(none))"
	@echo "All available testbenches passed."

test_%:
	@mkdir -p $(BUILD)
	$(IVERILOG) $(IVFLAGS) -s tb_$* -o $(BUILD)/tb_$*.vvp $(SRC_$*)
	cd $(BUILD) && $(VVP) -n tb_$*.vvp | tee tb_$*.log
	@grep -q "^PASS" $(BUILD)/tb_$*.log && ! grep -q "FAIL" $(BUILD)/tb_$*.log \
		|| (echo "*** tb_$* FAILED (see $(BUILD)/tb_$*.log)"; exit 1)

TEST ?= uart_tx
wave: test_$(TEST)
	$(GTKWAVE) $(BUILD)/tb_$(TEST).vcd &

clean:
	rm -rf $(BUILD)
