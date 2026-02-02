# NPC Modulator

VHDL modules for PWM modulation of 3-level NPC (Neutral Point Clamped) inverters.

## 📁 Directory Structure

```
npc_modulator/
├── src/
│   ├── NPCModulator.vhd      # PWM state generator (carrier comparison)
│   ├── NPCGateDriver.vhd     # Safe transition manager with dead time
│   └── NPCManager.vhd        # Top-level manager (combines modulator + 3x drivers)
├── test/
│   ├── tb_NPCModulator.vhd   # Modulator testbench
│   ├── tb_NPCGateDriver.vhd  # Gate driver testbench (24 tests)
│   └── tb_NPCManager.vhd     # Manager testbench
├── Makefile                  # Build automation
└── README.md                 # This file
```

## 🔌 NPC 3-Level Topology

The 3-level NPC inverter uses 4 switches per phase (S1, S2, S3, S4):

```
         +Vdc/2
            │
           ┌┴┐
           │S1│ ←── Upper switch
           └┬┘
            │
           ┌┴┐
           │S2│
           └┬┘
            ├──────► Output (phase A, B, or C)
           ┌┴┐
           │S3│
           └┬┘
            │
           ┌┴┐
           │S4│ ←── Lower switch
           └┬┘
            │
         -Vdc/2

    Clamping diodes connect the
    midpoint to neutral (not shown)
```

### Valid States

| State | S1 | S2 | S3 | S4 | Voltage | Code |
|-------|:--:|:--:|:--:|:--:|:-------:|:----:|
| **POS**     | ON  | ON  | OFF | OFF | +Vdc/2 | `"11"` |
| **NEUTRAL** | OFF | ON  | ON  | OFF | 0      | `"01"` |
| **NEG**     | OFF | OFF | ON  | ON  | -Vdc/2 | `"00"` |

### Valid Transitions

```
    ┌─────────────────────────────────────┐
    │                                     │
    ▼                                     │
  ┌─────┐     ┌─────────┐     ┌─────┐    │
  │ POS │◄───►│ NEUTRAL │◄───►│ NEG │    │
  └─────┘     └─────────┘     └─────┘    │
    │                                     │
    └─────────── FORBIDDEN ──────────────┘
                  (fault!)
```

**Fundamental rule:** Always pass through NEUTRAL. Never POS → NEG directly!

---

## 📦 Modules

### 1. NPCModulator

**Purpose:** Compares sinusoidal references with a triangular carrier to generate NPC states.

#### Entity Declaration

```vhdl
Entity NPCModulator is
    Generic (
        CLK_FREQ         : natural := 100_000_000;  -- System clock frequency (Hz)
        PWM_FREQ         : natural := 20_000;       -- PWM switching frequency (Hz)
        DATA_WIDTH       : natural := 32;           -- Reference signal bit width
        LOAD_BOTH_EDGES  : boolean := false;        -- Sample at valley AND peak
        OUTPUT_REG       : boolean := true          -- Add output register stage
    );
    Port (
        sysclk, reset_n  : in  std_logic;
        va_ref_i, vb_ref_i, vc_ref_i : in  std_logic_vector;  -- Signed references
        carrier_tick_o   : out std_logic;           -- Carrier valley tick
        sample_tick_o    : out std_logic;           -- Reference sampling tick
        state_a_o, state_b_o, state_c_o : out std_logic_vector(1 downto 0)
    );
End entity;
```

#### Architecture: 4-Stage Pipeline

The modulator uses a pipelined architecture for optimal FPGA timing:

```
┌────────────────┐   ┌────────────────┐   ┌────────────────┐   ┌────────────────┐   ┌────────────────┐
│    Stage 0     │   │    Stage 1     │   │    Stage 2     │   │    Stage 3     │   │    Stage 4     │
│                │   │                │   │                │   │                │   │   (optional)   │
│   Triangular   │──►│   Reference    │──►│  Absolute +    │──►│  Comparison +  │──►│    Output      │──► states
│    Carrier     │   │   Sampling     │   │    Scaling     │   │   NPC Logic    │   │   Register     │
└────────────────┘   └────────────────┘   └────────────────┘   └────────────────┘   └────────────────┘
       s0_               s1_                   s2_                   s3_
```

##### Stage 0: Triangular Carrier Generation

Generates a symmetric triangular waveform for PWM comparison:

```
    CARRIER_HALF ─┐      ╱╲      ╱╲      ╱╲
                  │     ╱  ╲    ╱  ╲    ╱  ╲
                  │    ╱    ╲  ╱    ╲  ╱    ╲
                0 ┴───╱──────╲╱──────╲╱──────╲───
                      │       │       │
                    valley   peak   valley
```

**Key signals:**
- `s0_carrier_ramp` - Current carrier value (unsigned)
- `s0_direction` - Ramp direction ('1' = rising, '0' = falling)
- `s0_valley` - Pulse at carrier minimum (period start)
- `s0_peak` - Pulse at carrier maximum

**Carrier timing parameters:**
```vhdl
constant CARRIER_PERIOD : natural := CLK_FREQ / PWM_FREQ;
constant CARRIER_HALF   : natural := CARRIER_PERIOD / 2;
constant CARRIER_BITS   : natural := log2_ceil(CARRIER_HALF);
```

##### Stage 1: Reference Sampling

Latches the three-phase references at carrier valley (and optionally peak):

- **LOAD_BOTH_EDGES = false:** Sample at valley only (standard mode)
- **LOAD_BOTH_EDGES = true:** Sample at valley AND peak (double update rate)

```vhdl
signal s1_va_latched : signed(DATA_WIDTH-1 downto 0);
signal s1_vb_latched : signed(DATA_WIDTH-1 downto 0);
signal s1_vc_latched : signed(DATA_WIDTH-1 downto 0);
```

##### Stage 2: Absolute Value + Scaling

Computes the absolute value and scales references to carrier range:

```vhdl
-- Scale factor calculation
constant SCALE_SHIFT : natural := DATA_WIDTH - 1 - CARRIER_BITS;

-- Result: reference magnitude in carrier units
signal s2_va_abs : unsigned(CARRIER_BITS-1 downto 0);
signal s2_va_sign : std_logic;  -- Preserved for polarity decision
```

The scaling extracts the MSBs after the sign bit to match carrier resolution.

##### Stage 3: Comparison + NPC Logic

Compares scaled reference magnitude with carrier and generates NPC state:

```vhdl
function npc_state(
    ref_mag  : unsigned;
    carrier  : unsigned;
    ref_sign : std_logic
) return std_logic_vector is
begin
    if ref_mag > carrier then
        if ref_sign = '0' then
            return "11";  -- POS (+Vdc/2)
        else
            return "00";  -- NEG (-Vdc/2)
        end if;
    else
        return "01";      -- NEUTRAL (0)
    end if;
end function;
```

##### Stage 4: Output Register (Optional)

When `OUTPUT_REG = true`, adds one cycle latency but improves timing.

**Total latency:**
- `OUTPUT_REG = false`: **3 clock cycles**
- `OUTPUT_REG = true`: **4 clock cycles**

---

### 2. NPCGateDriver

**Purpose:** Receives states from NPCModulator and manages safe transitions with:
- ✅ Dead time between complementary switches
- ✅ Minimum pulse width enforcement
- ✅ Forbidden transition detection
- ✅ Ordered shutdown sequence
- ✅ Safe startup (must start from NEUTRAL)

#### Entity Declaration

```vhdl
Entity NPCGateDriver is
    Generic (
        MIN_PULSE_WIDTH : integer := 100;   -- Minimum pulse width (clock cycles)
        DEAD_TIME       : integer := 50;    -- Dead time (clock cycles)
        WAIT_STATE_CNT  : integer := 100000 -- Wait state counter (~1ms at 100MHz)
    );
    Port (
        sysclk      : in std_logic;
        reset_n     : in std_logic;

        -- Control interface
        en_i        : in std_logic;         -- PWM enable
        sync_i      : in std_logic;         -- Sync pulse (carrier valley)
        clear_i     : in std_logic;         -- Clear faults

        -- NPC state input (2 bits from NPCModulator)
        state_i     : in std_logic_vector(1 downto 0);

        -- Gate outputs (4 bits to drivers: S4 S3 S2 S1)
        pwm_o       : out std_logic_vector(3 downto 0);

        -- Status/Fault outputs
        min_fault_o : out std_logic;        -- Min pulse violation (pulse)
        fs_fault_o  : out std_logic;        -- Forbidden state (pulse)
        fault_o     : out std_logic;        -- Latched fault flag
        pwm_on_o    : out std_logic         -- PWM is active (not OFF)
    );
End entity;
```

#### Architecture: FSM with Safety Features

The gate driver implements a finite state machine with strict timing enforcement:

##### FSM States

| State | Gate Pattern | Description |
|-------|:------------:|-------------|
| `ST_OFF` | `"0000"` | All gates OFF, waiting for safe startup |
| `ST_POS` | `"0011"` | Positive state (S1+S2 ON) |
| `ST_POS_DEAD` | `"0010"` | Dead time: S2 only (POS ↔ NEUTRAL) |
| `ST_ZERO` | `"0110"` | Neutral state (S2+S3 ON) |
| `ST_NEG_DEAD` | `"0100"` | Dead time: S3 only (NEUTRAL ↔ NEG) |
| `ST_NEG` | `"1100"` | Negative state (S3+S4 ON) |
| `WAIT_ST` | `"0000"` | Shutdown wait before returning to OFF |

##### State Diagram

```
                         ┌─────────────────────┐
                         │      ST_OFF         │
                         │  (pwm = "0000")     │
                         └──────────┬──────────┘
                                    │
            en_sync=1 AND fault=0 AND state_i="01" (rising edge)
                                    │
                                    ▼
                         ┌─────────────────────┐
              ┌─────────►│      ST_ZERO        │◄─────────┐
              │          │  (pwm = "0110")     │          │
              │          └──────────┬──────────┘          │
              │                     │                     │
         dt_ok=1               minw_ok=1             dt_ok=1
              │          ┌──────────┴──────────┐          │
              │          │                     │          │
              ▼          ▼                     ▼          ▼
    ┌─────────────────────┐           ┌─────────────────────┐
    │    ST_POS_DEAD      │           │    ST_NEG_DEAD      │
    │  (pwm = "0010")     │           │  (pwm = "0100")     │
    │   S2 only ON        │           │   S3 only ON        │
    └──────────┬──────────┘           └──────────┬──────────┘
               │                                  │
          dt_ok=1                            dt_ok=1
               │                                  │
               ▼                                  ▼
    ┌─────────────────────┐           ┌─────────────────────┐
    │      ST_POS         │           │      ST_NEG         │
    │  (pwm = "0011")     │           │  (pwm = "1100")     │
    │   S1+S2 ON          │           │   S3+S4 ON          │
    └─────────────────────┘           └─────────────────────┘
```

##### Signal Naming Convention

The architecture uses a traditional two-signal naming convention:
- `signal` - Registered value (updated on clock edge)
- `signal_next` - Combinational next-state logic

```vhdl
-- Example:
signal state        : fsm_state_t := ST_OFF;  -- Registered
signal state_next   : fsm_state_t;            -- Combinational

signal pwm          : std_logic_vector(3 downto 0);
signal pwm_next     : std_logic_vector(3 downto 0);
```

##### TurnOff Sequence (Priority Block)

When `en_i = '0'` or `fault = '1'`, the TurnOff logic takes priority over normal FSM operation:

```
Ordered Shutdown Sequence:
══════════════════════════

ST_POS ───► ST_POS_DEAD ───► WAIT_ST ───► ST_OFF
                                ▲
ST_ZERO ────────────────────────┤
                                │
ST_NEG ───► ST_NEG_DEAD ────────┘
```

The shutdown sequence:
1. **Wait for min pulse** - Cannot leave current state until `minw_ok = '1'`
2. **Insert dead time** - POS→POS_DEAD or NEG→NEG_DEAD
3. **Wait dead time complete** - Stay in dead state until `dt_ok_redge = '1'`
4. **Enter WAIT_ST** - Wait for `en_i = '0'` before counting
5. **Count WAIT_STATE_CNT cycles** - Prevents immediate re-enable
6. **Return to ST_OFF** - Ready for safe startup

##### Dead Time Insertion

During transitions, an intermediate state ensures dead time:

```
POS → NEUTRAL:
  Before:  S1=ON,  S2=ON,  S3=OFF, S4=OFF  (VEC_POS = "0011")
  Dead:    S1=OFF, S2=ON,  S3=OFF, S4=OFF  (VEC_ZERO_P = "0010") ← S2 only
  After:   S1=OFF, S2=ON,  S3=ON,  S4=OFF  (VEC_ZERO = "0110")

NEUTRAL → NEG:
  Before:  S1=OFF, S2=ON,  S3=ON,  S4=OFF  (VEC_ZERO = "0110")
  Dead:    S1=OFF, S2=OFF, S3=ON,  S4=OFF  (VEC_ZERO_N = "0100") ← S3 only
  After:   S1=OFF, S2=OFF, S3=ON,  S4=ON   (VEC_NEG = "1100")
```

##### Timing Counters

A single counter manages both dead time and minimum pulse width:

```vhdl
signal ctr      : integer range 0 to Max(MIN_PULSE_WIDTH, DEAD_TIME);
signal ctr_next : integer range 0 to Max(MIN_PULSE_WIDTH, DEAD_TIME);

-- Timing flags
signal minw_ok  : std_logic;  -- '1' when ctr >= MIN_PULSE_WIDTH - 1
signal dt_ok    : std_logic;  -- '1' when ctr >= DEAD_TIME - 1
```

The counter resets on every state change and increments each clock cycle.

---

## 🚀 Safe Startup

The system implements a safe startup with the following conditions:

1. **Synchronized enable:** `en_i` is sampled only on `sync_i` pulse (carrier valley)
2. **Required initial state:** First state must be NEUTRAL (`"01"`)
3. **Edge detection:** Requires a transition TO NEUTRAL (cannot already be in NEUTRAL)
4. **No faults:** `fault = '0'`

```vhdl
-- Startup conditions (in ST_OFF state):
if (en_sync = '1') and (fault = '0') and 
   (state_i = ST_ZERO_IN) and (state_i_last /= ST_ZERO_IN) then
    state_next <= ST_ZERO;
end if;
```

### Why Synchronize Enable?

```
         sync_i (carrier valley)
            ▼         ▼         ▼
Clock:  ────┴─────────┴─────────┴─────────
            │         │         │
enable_i: ──┘         │         │
            ▲         │         │
            │         ▼         │
en_sync:    │         ┘─────────┘
            │
     enable changes here, but is
     only seen at next sync pulse
```

This prevents enable changes mid-cycle from causing undefined behavior.

---

## ⚠️ Fault Detection

The GateDriver detects **forbidden** transitions:

| From | To | Result |
|------|-----|--------|
| POS | NEG | `fault = '1'` (latched) |
| NEG | POS | `fault = '1'` (latched) |
| POS | NEUTRAL | ✅ OK (via dead time) |
| NEUTRAL | NEG | ✅ OK (via dead time) |

When `fault = '1'`:
1. Initiates shutdown sequence immediately
2. Flag remains until `clear_i = '1'`
3. System can only restart after clear + startup conditions

**Fault outputs:**
- `fs_fault_o` - Pulse (1 clock) on forbidden state detection
- `fault_o` - Latched fault flag (stays high until cleared)
- `min_fault_o` - Minimum pulse violation indicator

---

## 🔌 Typical Connection

```vhdl
-- Three-phase NPC modulator instantiation
modulator: entity work.NPCModulator
    generic map (
        CLK_FREQ    => 100_000_000,
        PWM_FREQ    => 20_000,
        DATA_WIDTH  => 32
    )
    port map (
        sysclk         => clk,
        reset_n        => rst_n,
        va_ref_i       => ref_a,
        vb_ref_i       => ref_b,
        vc_ref_i       => ref_c,
        carrier_tick_o => carrier_tick,
        sample_tick_o  => sample_tick,
        state_a_o      => state_a,
        state_b_o      => state_b,
        state_c_o      => state_c
    );

-- Gate driver for phase A
gate_driver_a: entity work.NPCGateDriver
    generic map (
        MIN_PULSE_WIDTH => 100,    -- 1us at 100MHz
        DEAD_TIME       => 50,     -- 500ns at 100MHz
        WAIT_STATE_CNT  => 100000  -- 1ms at 100MHz
    )
    port map (
        sysclk      => clk,
        reset_n     => rst_n,
        en_i        => pwm_enable,
        sync_i      => carrier_tick,
        clear_i     => fault_clear,
        state_i     => state_a,
        pwm_o       => gates_a,      -- Connect to IGBT drivers
        min_fault_o => open,
        fs_fault_o  => fs_fault_a,
        fault_o     => fault_a,
        pwm_on_o    => active_a
    );

-- Repeat for phases B and C with state_b, state_c
```

---

## 🧪 Simulation

### Using Makefile

```bash
cd common/modules/npc_modulator

# Run NPCManager simulation (default)
make

# Run NPCModulator simulation
make sim

# Run NPCGateDriver simulation
make sim-driver

# Run NPCManager simulation
make sim-manager

# Open waveform viewer
make wave-manager

# Clean generated files
make clean
```

### Manual GHDL Commands

```bash
# Compile all sources
ghdl -a -fsynopsys src/NPCModulator.vhd
ghdl -a -fsynopsys src/NPCGateDriver.vhd
ghdl -a -fsynopsys src/NPCManager.vhd
ghdl -a -fsynopsys test/tb_NPCManager.vhd
ghdl -e -fsynopsys tb_NPCManager

# Run simulation
ghdl -r -fsynopsys tb_NPCManager --wave=test/waves_manager.ghw

# View waveforms
gtkwave test/waves_manager.ghw
```

### Testbench Coverage

**tb_NPCGateDriver** - 24 tests covering:

| Test Group | Tests | Description |
|------------|:-----:|-------------|
| T1: Reset state | 1 | Verify PWM outputs are 0000 after reset |
| T2-T3: Startup blocking | 2 | Cannot start directly to POS or NEG |
| T4: Valid startup | 1 | Proper startup to NEUTRAL state |
| T5: POS transition | 1 | NEUTRAL → POS with dead time |
| T6: Back to NEUTRAL | 1 | POS → NEUTRAL with dead time |
| T7: NEG transition | 1 | NEUTRAL → NEG with dead time |
| T8: Back to NEUTRAL | 1 | NEG → NEUTRAL with dead time |
| T9-T10: Forbidden | 2 | POS↔NEG triggers fault |
| T11-T14: Shutdown | 4 | Ordered shutdown from all states |
| T15: Dead time | 4 | Dead time timing verification |
| T16: Min pulse | 4 | Minimum pulse width enforcement |
| T17: Enable sync | 2 | Enable synchronization with carrier |

**tb_NPCManager** - 16 tests covering:

| Test Group | Tests | Description |
|------------|:-----:|-------------|
| T1: Reset state | 4 | All phases OFF after reset |
| T2: Valid startup | 1 | Enable with neutral reference |
| T3-T4: Pos/Neg refs | 2 | Positive and negative modulation |
| T5: Three-phase | 1 | Balanced three-phase operation |
| T6: External fault | 2 | Fault input shuts down PWM |
| T7: Re-enable | 1 | Recovery after fault clear |
| T8: Disable | 2 | Clean shutdown on disable |

---

## 📊 Typical Parameters

| Parameter | Typical Value | Description |
|-----------|---------------|-------------|
| CLK_FREQ | 100 MHz | FPGA clock frequency |
| PWM_FREQ | 10-50 kHz | Switching frequency |
| DEAD_TIME | 50-100 cycles | 500ns-1µs at 100MHz |
| MIN_PULSE_WIDTH | 100-200 cycles | 1-2µs at 100MHz |
| WAIT_STATE_CNT | 100000 cycles | 1ms at 100MHz |

### PWM Resolution Calculation

```
Resolution = CLK_FREQ / (2 × PWM_FREQ)

Example: 100MHz / (2 × 20kHz) = 2500 levels ≈ 11 bits
```

### Dead Time Calculation

```
Dead Time (ns) = DEAD_TIME × (1 / CLK_FREQ) × 1e9

Example: 50 cycles × 10ns = 500ns
```

---

## 📝 Changelog

### v2.1 (Current)
- NPCGateDriver: Changed interface to 2-bit input (matches modulator output)
- Added `fault_o` latched output (separate from `fs_fault_o` pulse)
- Traditional signal naming convention (`signal` / `signal_next`)
- Comprehensive testbench with 24 tests
- Complete English documentation

### v2.0 (01-02-2026)
- Renamed NPCHandler → NPCModulator
- Created separate NPCGateDriver module
- Explicit pipeline with s0_, s1_, s2_, s3_ naming
- Safe startup implementation

### v1.0 (25-01-2026)
- Initial NPCHandler version

---

## 📄 License

Copyright (c) 2026 - All rights reserved.

---

## 👤 Author

**Uriel Abe Contardi**  
📧 urielcontardi@hotmail.com

1. **Enable sincronizado:** O `enable_i` só é amostrado no pulso `sync_i` (vale da portadora)
2. **Estado inicial obrigatório:** O primeiro estado deve ser NEUTRAL (`"01"`)
3. **Detecção de borda:** Precisa haver uma transição para NEUTRAL (não pode já estar em NEUTRAL)
4. **Sem falhas:** `fault = '0'`

```vhdl
-- Condições de startup:
if enable_sync = '1' and fault = '0' then
    if state_in = "01" and startup_valid = '1' then
        next_state := ST_NEUTRAL;
    end if;
end if;
```

### Por que sincronizar o enable?

```
         sync_i (carrier valley)
            ▼         ▼         ▼
Clock:  ────┴─────────┴─────────┴─────────
            │         │         │
enable_i: ──┘         │         │
            ▲         │         │
            │         ▼         │
enable_sync:│         ┘─────────┘
            │
     enable muda aqui, mas só é
     visto no próximo sync
```

Isso evita que mudanças no enable no meio de um ciclo PWM causem comportamento indefinido.

---

## ⚠️ Detecção de Falhas

O GateDriver detecta transições **proibidas**:

| De | Para | Resultado |
|----|------|-----------|
| POS | NEG | `fault = '1'` |
| NEG | POS | `fault = '1'` |
| POS | NEUTRAL | ✅ OK (via dead time) |
| NEUTRAL | NEG | ✅ OK (via dead time) |

Quando `fault = '1'`:
1. Inicia sequência de desligamento imediatamente
2. Flag permanece até `clear_i = '1'`
3. Sistema só pode reiniciar após clear + condições de startup

---

## 🔌 Conexão Típica

```vhdl
-- Instanciação de um leg completo (fase A)
modulator_a: entity work.NPCModulator
    generic map (
        CLK_FREQ    => 100_000_000,
        PWM_FREQ    => 20_000,
        DATA_WIDTH  => 32
    )
    port map (
        sysclk         => clk,
        reset_n        => rst_n,
        va_ref_i       => ref_a,
        vb_ref_i       => ref_b,
        vc_ref_i       => ref_c,
        carrier_tick_o => carrier_tick,
        sample_tick_o  => sample_tick,
        state_a_o      => state_a,
        state_b_o      => state_b,
        state_c_o      => state_c
    );

gate_driver_a: entity work.NPCGateDriver
    generic map (
        CLK_FREQ     => 100_000_000,
        DEAD_TIME_NS => 500,
        MIN_PULSE_NS => 1000,
        SHUTDOWN_MS  => 1
    )
    port map (
        sysclk   => clk,
        reset_n  => rst_n,
        enable_i => pwm_enable,
        sync_i   => carrier_tick,
        clear_i  => fault_clear,
        state_i  => state_a,
        gates_o  => gates_a,      -- Conectar aos drivers IGBT
        fault_o  => fault_a,
        active_o => active_a
    );
```

---

## 🧪 Simulação

### Usando Make

```bash
cd common/modules/npc_modulator

# Simulação completa (40ms = 2 ciclos de 50Hz)
make sim

# Simulação rápida (5ms)
make quick

# Abrir waveform
make wave

# Limpar arquivos gerados
make clean
```

### Manual com GHDL

```bash
# Compilar
ghdl -a -fsynopsys src/NPCModulator.vhd
ghdl -a -fsynopsys src/NPCGateDriver.vhd
ghdl -a -fsynopsys test/tb_NPCModulator.vhd
ghdl -e -fsynopsys tb_NPCModulator

# Executar
ghdl -r -fsynopsys tb_NPCModulator --wave=test/waves.ghw --stop-time=5ms

# Visualizar
gtkwave test/waves.ghw
```

---

## 📊 Parâmetros Típicos

| Parâmetro | Valor Típico | Descrição |
|-----------|--------------|-----------|
| CLK_FREQ | 100 MHz | Clock do FPGA |
| PWM_FREQ | 10-50 kHz | Frequência de chaveamento |
| DEAD_TIME_NS | 200-1000 ns | Depende dos IGBTs |
| MIN_PULSE_NS | 500-2000 ns | Evita pulsos muito curtos |
| SHUTDOWN_MS | 1-5 ms | Tempo de espera no shutdown |

### Cálculo de Resolução PWM

```
Resolução = CLK_FREQ / (2 × PWM_FREQ)

Exemplo: 100MHz / (2 × 20kHz) = 2500 níveis = ~11 bits
```

---

## 📝 Changelog

### v2.0 (01-02-2026)
- Renomeado NPCHandler → NPCModulator
- Criado NPCGateDriver separado
- Pipeline explícito com nomenclatura s0_, s1_, s2_, s3_
- Startup seguro implementado
- Documentação completa

### v1.0 (25-01-2026)
- Primeira versão do NPCHandler
