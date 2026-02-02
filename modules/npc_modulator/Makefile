# Makefile for NPC Modulator modules
# Usage:
#   make              - Compile and run NPCManager simulation (default)
#   make sim          - Compile and run NPCModulator simulation
#   make sim-driver   - Compile and run NPCGateDriver simulation
#   make sim-manager  - Compile and run NPCManager simulation
#   make sim-sine     - Run sinusoidal three-phase simulation (for visualization)
#   make wave-sine    - Run sine simulation and open GTKWave
#   make compile      - Compile only
#   make clean        - Remove generated files

# Configuration
GHDL        := ghdl
GHDL_FLAGS  := -fsynopsys
GTKWAVE     := gtkwave

# Directories
SRC_DIR     := src
TEST_DIR    := test

# Source files
SRC_MODULATOR   := $(SRC_DIR)/NPCModulator.vhd
SRC_DRIVER      := $(SRC_DIR)/NPCGateDriver.vhd
SRC_MANAGER     := $(SRC_DIR)/NPCManager.vhd

# Testbenches
TB_MODULATOR    := $(TEST_DIR)/tb_NPCModulator.vhd
TB_DRIVER       := $(TEST_DIR)/tb_NPCGateDriver.vhd
TB_MANAGER      := $(TEST_DIR)/tb_NPCManager.vhd
TB_SINE         := $(TEST_DIR)/tb_NPCManager_Sine.vhd

# Entities
ENTITY_MODULATOR := tb_NPCModulator
ENTITY_DRIVER    := tb_NPCGateDriver
ENTITY_MANAGER   := tb_NPCManager
ENTITY_SINE      := tb_NPCManager_Sine

# Wave files
WAVE_MODULATOR  := $(TEST_DIR)/waves_modulator.ghw
WAVE_DRIVER     := $(TEST_DIR)/waves_driver.ghw
WAVE_MANAGER    := $(TEST_DIR)/waves_manager.ghw
WAVE_SINE       := $(TEST_DIR)/waves_sine.ghw

# Simulation time
SIM_TIME          := 40ms
SIM_TIME_DRIVER   := 10ms
SIM_TIME_MANAGER  := 5ms
SIM_TIME_SINE     := 70ms

# Default target
.PHONY: all
all: sim-manager

# Compile all sources
.PHONY: compile
compile:
	@echo "=== Compiling VHDL sources ==="
	$(GHDL) analyze $(GHDL_FLAGS) $(SRC_MODULATOR) $(SRC_DRIVER) $(SRC_MANAGER)
	$(GHDL) analyze $(GHDL_FLAGS) $(TB_MODULATOR) $(TB_DRIVER) $(TB_MANAGER) $(TB_SINE)
	$(GHDL) elaborate $(GHDL_FLAGS) $(ENTITY_MODULATOR)
	$(GHDL) elaborate $(GHDL_FLAGS) $(ENTITY_DRIVER)
	$(GHDL) elaborate $(GHDL_FLAGS) $(ENTITY_MANAGER)
	$(GHDL) elaborate $(GHDL_FLAGS) $(ENTITY_SINE)
	@echo "=== Compilation successful ==="

# Run NPCModulator simulation
.PHONY: sim
sim: compile
	@echo "=== Running NPCModulator simulation ($(SIM_TIME)) ==="
	$(GHDL) run $(GHDL_FLAGS) $(ENTITY_MODULATOR) --wave=$(WAVE_MODULATOR) --stop-time=$(SIM_TIME) 2>&1 | grep -E "(Tempo:|simulation|error|state)" | tail -20
	@echo "=== Simulation complete: $(WAVE_MODULATOR) ==="

# Run NPCGateDriver simulation
.PHONY: sim-driver
sim-driver: compile
	@echo "=== Running NPCGateDriver simulation ($(SIM_TIME_DRIVER)) ==="
	$(GHDL) run $(GHDL_FLAGS) $(ENTITY_DRIVER) --wave=$(WAVE_DRIVER) --stop-time=$(SIM_TIME_DRIVER) 2>&1 | grep -E "(PASS|FAIL|TEST|Summary|error)" | tail -30
	@echo "=== Simulation complete: $(WAVE_DRIVER) ==="

# Run NPCManager simulation
.PHONY: sim-manager
sim-manager: compile
	@echo "=== Running NPCManager simulation ($(SIM_TIME_MANAGER)) ==="
	$(GHDL) run $(GHDL_FLAGS) $(ENTITY_MANAGER) --wave=$(WAVE_MANAGER) --stop-time=$(SIM_TIME_MANAGER) 2>&1 | grep -E "(PASS|FAIL|TEST|Summary|T[0-9]|error)" | tail -40
	@echo "=== Simulation complete: $(WAVE_MANAGER) ==="

# Run sinusoidal simulation (for visualization)
.PHONY: sim-sine
sim-sine: compile
	@echo "=== Running Sinusoidal simulation ($(SIM_TIME_SINE)) ==="
	@echo "    This simulates 3 cycles of 50Hz fundamental..."
	$(GHDL) run $(GHDL_FLAGS) $(ENTITY_SINE) --wave=$(WAVE_SINE) --stop-time=$(SIM_TIME_SINE) 2>&1 | grep -E "(===|Simulation|Suggested|PWM)" | tail -20
	@echo "=== Simulation complete: $(WAVE_SINE) ==="
	@echo "    Run 'make wave-sine' to open GTKWave"

# Run simulation and open GTKWave
.PHONY: wave
wave: sim
	@echo "=== Opening GTKWave ==="
	$(GTKWAVE) $(WAVE_MODULATOR) &

# Open driver waveform
.PHONY: wave-driver
wave-driver: sim-driver
	@echo "=== Opening GTKWave (Driver) ==="
	$(GTKWAVE) $(WAVE_DRIVER) &

# Open manager waveform
.PHONY: wave-manager
wave-manager: sim-manager
	@echo "=== Opening GTKWave (Manager) ==="
	$(GTKWAVE) $(WAVE_MANAGER) &

# Open sine waveform
.PHONY: wave-sine
wave-sine: sim-sine
	@echo "=== Opening GTKWave (Sine) ==="
	$(GTKWAVE) $(WAVE_SINE) $(TEST_DIR)/npc_viewer.gtkw &

# View sine with saved config (after simulation already run)
.PHONY: view-sine
view-sine:
	@echo "=== Opening GTKWave with saved layout ==="
	cd $(TEST_DIR) && $(GTKWAVE) waves_sine.ghw npc_viewer.gtkw &

# Quick simulation (shorter time for fast iteration)
.PHONY: quick
quick: compile
	@echo "=== Quick simulation (5ms) ==="
	$(GHDL) run $(GHDL_FLAGS) $(ENTITY_MODULATOR) --wave=$(WAVE_MODULATOR) --stop-time=5ms 2>&1 | grep -E "(Tempo:|simulation|error)" | tail -10
	@echo "=== Quick simulation complete ==="

# Clean generated files
.PHONY: clean
clean:
	@echo "=== Cleaning generated files ==="
	rm -f *.cf
	rm -f $(TEST_DIR)/*.ghw
	rm -f $(ENTITY_MODULATOR) $(ENTITY_DRIVER) $(ENTITY_MANAGER) $(ENTITY_SINE)
	@echo "=== Clean complete ==="

# Help
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  make              - Run NPCManager simulation (default)"
	@echo "  make sim          - Run NPCModulator simulation ($(SIM_TIME))"
	@echo "  make sim-driver   - Run NPCGateDriver simulation ($(SIM_TIME_DRIVER))"
	@echo "  make sim-manager  - Run NPCManager simulation ($(SIM_TIME_MANAGER))"
	@echo "  make sim-sine     - Run 3-phase sine simulation ($(SIM_TIME_SINE)) - VISUALIZATION"
	@echo "  make wave-sine    - Run sine simulation and open GTKWave"
	@echo "  make quick        - Quick NPCModulator simulation (5ms)"
	@echo "  make wave         - Run and open NPCModulator waveform"
	@echo "  make wave-driver  - Run and open NPCGateDriver waveform"
	@echo "  make wave-manager - Run and open NPCManager waveform"
	@echo "  make compile      - Compile only (no simulation)"
	@echo "  make clean        - Remove generated files"
	@echo "  make help         - Show this help"
