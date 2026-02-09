# Makefile for FIFO module
# Usage:
#   make              - Compile and run default simulation
#   make sim          - Compile and run registered output mode test
#   make sim-async    - Compile and run async output mode test
#   make sim-all      - Run all simulations
#   make wave         - Run simulation and open GTKWave
#   make wave-async   - Run async simulation and open GTKWave
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
SRC_FIFO    := $(SRC_DIR)/fifo.vhd

#==============================================================================
# Testbenches
#==============================================================================
TB_FIFO       := $(TEST_DIR)/tb_Fifo.vhd
TB_FIFO_ASYNC := $(TEST_DIR)/tb_Fifo_Async.vhd

#==============================================================================
# Entity names
#==============================================================================
ENTITY_FIFO       := tb_Fifo
ENTITY_FIFO_ASYNC := tb_Fifo_Async

#==============================================================================
# Wave files
#==============================================================================
WAVE_FIFO       := $(TEST_DIR)/waves_fifo.ghw
WAVE_FIFO_ASYNC := $(TEST_DIR)/waves_fifo_async.ghw

#==============================================================================
# Simulation time
#==============================================================================
SIM_TIME       := 10us
SIM_TIME_ASYNC := 5us

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
	@echo "=== Compiling VHDL sources ==="
	$(GHDL) analyze $(GHDL_FLAGS) $(SRC_FIFO)
	$(GHDL) analyze $(GHDL_FLAGS) $(TB_FIFO) $(TB_FIFO_ASYNC)
	$(GHDL) elaborate $(GHDL_FLAGS) $(ENTITY_FIFO)
	$(GHDL) elaborate $(GHDL_FLAGS) $(ENTITY_FIFO_ASYNC)
	@echo "=== Compilation successful ==="

#==============================================================================
# Run FIFO simulation (registered output mode)
#==============================================================================
.PHONY: sim
sim: compile
	@echo "=== Running FIFO simulation - Registered Mode ($(SIM_TIME)) ==="
	$(GHDL) run $(GHDL_FLAGS) $(ENTITY_FIFO) --wave=$(WAVE_FIFO) --stop-time=$(SIM_TIME)
	@echo "=== Simulation complete: $(WAVE_FIFO) ==="

#==============================================================================
# Run FIFO simulation (async output mode)
#==============================================================================
.PHONY: sim-async
sim-async: compile
	@echo "=== Running FIFO simulation - Async Mode ($(SIM_TIME_ASYNC)) ==="
	$(GHDL) run $(GHDL_FLAGS) $(ENTITY_FIFO_ASYNC) --wave=$(WAVE_FIFO_ASYNC) --stop-time=$(SIM_TIME_ASYNC)
	@echo "=== Simulation complete: $(WAVE_FIFO_ASYNC) ==="

#==============================================================================
# Run all simulations
#==============================================================================
.PHONY: sim-all
sim-all: sim sim-async
	@echo "=== All simulations complete ==="

#==============================================================================
# Run simulation and open GTKWave
#==============================================================================
.PHONY: wave
wave: sim
	@echo "=== Opening GTKWave ==="
	$(GTKWAVE) $(WAVE_FIFO) &

.PHONY: wave-async
wave-async: sim-async
	@echo "=== Opening GTKWave (Async Mode) ==="
	$(GTKWAVE) $(WAVE_FIFO_ASYNC) &

#==============================================================================
# Quick simulation (for fast iteration)
#==============================================================================
.PHONY: quick
quick: compile
	@echo "=== Quick simulation (2us) ==="
	$(GHDL) run $(GHDL_FLAGS) $(ENTITY_FIFO) --wave=$(WAVE_FIFO) --stop-time=2us
	@echo "=== Quick simulation complete ==="

#==============================================================================
# Clean generated files
#==============================================================================
.PHONY: clean
clean:
	@echo "=== Cleaning generated files ==="
	rm -f *.cf
	rm -f $(TEST_DIR)/*.ghw
	rm -f $(ENTITY_FIFO) $(ENTITY_FIFO_ASYNC)
	rm -f *.o
	rm -f work-obj*.cf
	@echo "=== Clean complete ==="

#==============================================================================
# Help
#==============================================================================
.PHONY: help
help:
	@echo "FIFO Module - Available targets:"
	@echo ""
	@echo "  make              - Run default simulation (registered mode)"
	@echo "  make sim          - Run FIFO simulation (registered output)"
	@echo "  make sim-async    - Run FIFO simulation (async/combinatorial output)"
	@echo "  make sim-all      - Run all simulations"
	@echo "  make wave         - Run simulation and open GTKWave"
	@echo "  make wave-async   - Run async simulation and open GTKWave"
	@echo "  make quick        - Quick simulation (2us)"
	@echo "  make compile      - Compile only (no simulation)"
	@echo "  make clean        - Remove generated files"
	@echo "  make help         - Show this help"
	@echo ""
	@echo "Configuration:"
	@echo "  DATA_WIDTH = 8 bits"
	@echo "  FIFO_DEPTH = 16 (registered) / 8 (async)"
