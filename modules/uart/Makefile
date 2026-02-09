# Makefile for UART modules
# Usage:
#   make              - Compile and run loopback simulation (default)
#   make sim          - Run loopback simulation (TX -> RX)
#   make sim-full     - Run UartFull simulation (with FIFOs)
#   make sim-all      - Run all simulations
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
FIFO_DIR    := ../fifo/src

#==============================================================================
# Source files
#==============================================================================
SRC_TX      := $(SRC_DIR)/UartTX.vhd
SRC_RX      := $(SRC_DIR)/UartRX.vhd
SRC_FULL    := $(SRC_DIR)/UartFull.vhd
SRC_FIFO    := $(FIFO_DIR)/fifo.vhd

#==============================================================================
# Testbenches
#==============================================================================
TB_LOOPBACK := $(TEST_DIR)/tb_UartLoopback.vhd
TB_FULL     := $(TEST_DIR)/tb_UartFull.vhd

#==============================================================================
# Entity names
#==============================================================================
ENTITY_LOOPBACK := tb_UartLoopback
ENTITY_FULL     := tb_UartFull

#==============================================================================
# Wave files
#==============================================================================
WAVE_LOOPBACK   := $(TEST_DIR)/waves_loopback.ghw
WAVE_FULL       := $(TEST_DIR)/waves_full.ghw

#==============================================================================
# Simulation time
# 10 bits per byte @ 115200 baud ≈ 87us per byte
# For ~15 bytes + margins: ~2ms should be enough
#==============================================================================
SIM_TIME        := 5ms
SIM_TIME_FULL   := 10ms

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
	$(GHDL) analyze $(GHDL_FLAGS) $(SRC_FIFO)
	$(GHDL) analyze $(GHDL_FLAGS) $(SRC_TX) $(SRC_RX) $(SRC_FULL)
	$(GHDL) analyze $(GHDL_FLAGS) $(TB_LOOPBACK) $(TB_FULL)
	$(GHDL) elaborate $(GHDL_FLAGS) $(ENTITY_LOOPBACK)
	$(GHDL) elaborate $(GHDL_FLAGS) $(ENTITY_FULL)
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
# Run UartFull simulation
#==============================================================================
.PHONY: sim-full
sim-full: compile
	@echo "=== Running UartFull simulation ($(SIM_TIME_FULL)) ==="
	@echo "    Complete UART with TX/RX FIFOs in loopback"
	$(GHDL) run $(GHDL_FLAGS) $(ENTITY_FULL) --wave=$(WAVE_FULL) --stop-time=$(SIM_TIME_FULL)
	@echo "=== Simulation complete: $(WAVE_FULL) ==="

#==============================================================================
# Run all simulations
#==============================================================================
.PHONY: sim-all
sim-all: sim sim-full
	@echo "=== All simulations complete ==="

#==============================================================================
# Run simulation and open GTKWave
#==============================================================================
.PHONY: wave
wave: sim
	@echo "=== Opening GTKWave ==="
	$(GTKWAVE) $(WAVE_LOOPBACK) &

.PHONY: wave-full
wave-full: sim-full
	@echo "=== Opening GTKWave (UartFull) ==="
	$(GTKWAVE) $(WAVE_FULL) &

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
	rm -f $(ENTITY_LOOPBACK) $(ENTITY_FULL)
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
	@echo "  make sim-full     - Run UartFull simulation (with FIFOs)"
	@echo "  make sim-all      - Run all simulations"
	@echo "  make wave         - Run loopback and open GTKWave"
	@echo "  make wave-full    - Run UartFull and open GTKWave"
	@echo "  make quick        - Quick simulation (1ms)"
	@echo "  make compile      - Compile only (no simulation)"
	@echo "  make clean        - Remove generated files"
	@echo "  make help         - Show this help"
	@echo ""
	@echo "Configuration:"
	@echo "  Clock:    100 MHz"
	@echo "  Baudrate: 115200 bps"
	@echo "  Data:     8 bits, 1 start, 1 stop"
