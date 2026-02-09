# Makefile for UART modules
# Usage:
#   make              - Compile and run loopback simulation (default)
#   make sim          - Run loopback simulation (TX -> RX)
#   make wave         - Run simulation and open GTKWave
#   make compile      - Compile only
#   make clean        - Remove generated files

#==============================================================================
# Configuration
#==============================================================================
GHDL        := ghdl
GHDL_FLAGS  := --std=08
GTKWAVE     := gtkwave

#==============================================================================
# Directories
#==============================================================================
SRC_DIR     := src
TEST_DIR    := test

#==============================================================================
# Source files
#==============================================================================
SRC_TX      := $(SRC_DIR)/UartTX.vhd
SRC_RX      := $(SRC_DIR)/UartRX.vhd

#==============================================================================
# Testbenches
#==============================================================================
TB_LOOPBACK := $(TEST_DIR)/tb_UartLoopback.vhd

#==============================================================================
# Entity names
#==============================================================================
ENTITY_LOOPBACK := tb_UartLoopback

#==============================================================================
# Wave files
#==============================================================================
WAVE_LOOPBACK   := $(TEST_DIR)/waves_loopback.ghw

#==============================================================================
# Simulation time
# 10 bits per byte @ 115200 baud ≈ 87us per byte
# For ~15 bytes + margins: ~2ms should be enough
#==============================================================================
SIM_TIME        := 5ms

#==============================================================================
# Default target
#==============================================================================
.PHONY: all
all: sim

#==============================================================================
# Compile all sources
#==============================================================================
.PHONY: compile
compile:
	@echo "=== Compiling UART sources ==="
	$(GHDL) analyze $(GHDL_FLAGS) $(SRC_TX) $(SRC_RX)
	$(GHDL) analyze $(GHDL_FLAGS) $(TB_LOOPBACK)
	$(GHDL) elaborate $(GHDL_FLAGS) $(ENTITY_LOOPBACK)
	@echo "=== Compilation successful ==="

#==============================================================================
# Run loopback simulation
#==============================================================================
.PHONY: sim
sim: compile
	@echo "=== Running UART Loopback simulation ($(SIM_TIME)) ==="
	@echo "    TX sends data, RX receives (loopback connection)"
	$(GHDL) run $(GHDL_FLAGS) $(ENTITY_LOOPBACK) --wave=$(WAVE_LOOPBACK) --stop-time=$(SIM_TIME)
	@echo "=== Simulation complete: $(WAVE_LOOPBACK) ==="

#==============================================================================
# Run simulation and open GTKWave
#==============================================================================
.PHONY: wave
wave: sim
	@echo "=== Opening GTKWave ==="
	$(GTKWAVE) $(WAVE_LOOPBACK) &

#==============================================================================
# Quick simulation (shorter time for fast iteration)
#==============================================================================
.PHONY: quick
quick: compile
	@echo "=== Quick simulation (1ms) ==="
	$(GHDL) run $(GHDL_FLAGS) $(ENTITY_LOOPBACK) --wave=$(WAVE_LOOPBACK) --stop-time=1ms
	@echo "=== Quick simulation complete ==="

#==============================================================================
# Clean generated files
#==============================================================================
.PHONY: clean
clean:
	@echo "=== Cleaning generated files ==="
	rm -f *.cf
	rm -f $(TEST_DIR)/*.ghw
	rm -f $(ENTITY_LOOPBACK)
	rm -f *.o
	rm -f work-obj*.cf
	@echo "=== Clean complete ==="

#==============================================================================
# Help
#==============================================================================
.PHONY: help
help:
	@echo "UART Module - Available targets:"
	@echo ""
	@echo "  make              - Run loopback simulation (default)"
	@echo "  make sim          - Run UART TX->RX loopback simulation"
	@echo "  make wave         - Run simulation and open GTKWave"
	@echo "  make quick        - Quick simulation (1ms)"
	@echo "  make compile      - Compile only (no simulation)"
	@echo "  make clean        - Remove generated files"
	@echo "  make help         - Show this help"
	@echo ""
	@echo "Configuration:"
	@echo "  Clock:    100 MHz"
	@echo "  Baudrate: 115200 bps"
	@echo "  Data:     8 bits, 1 start, 1 stop"
