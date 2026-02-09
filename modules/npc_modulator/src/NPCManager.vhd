--! \file       NPCManager.vhd
--!
--! \brief      NPC (Neutral Point Clamped) 3-level PWM Manager for three-phase inverters.
--!             Combines NPCModulator and NPCGateDriver into a single top-level module.
--!
--! \author     Uriel Abe Contardi (urielcontardi@hotmail.com)
--! \date       01-02-2026
--!
--! \version    1.0
--!
--! \copyright  Copyright (c) 2026 - All Rights reserved.
--!
--! \details    This module instantiates:
--!             - 1x NPCModulator: Generates NPC states from voltage references
--!             - 3x NPCGateDriver: Safe gate driving with dead time (one per phase)
--!
--!             Block diagram:
--!             ┌─────────────────────────────────────────────────────────────┐
--!             │                      NPCManager                             │
--!             │                                                             │
--!             │  ┌─────────────────┐                                        │
--!             │  │                 │  state_a   ┌──────────────┐  pwm_a     │
--!             │  │                 ├───────────►│ GateDriver A ├──────────► │
--!             │  │                 │            └──────────────┘            │
--!             │  │  NPCModulator   │  state_b   ┌──────────────┐  pwm_b     │
--!             │  │                 ├───────────►│ GateDriver B ├──────────► │
--!             │  │                 │            └──────────────┘            │
--!             │  │                 │  state_c   ┌──────────────┐  pwm_c     │
--!             │  │                 ├───────────►│ GateDriver C ├──────────► │
--!             │  └─────────────────┘            └──────────────┘            │
--!             └─────────────────────────────────────────────────────────────┘
--!
--!             Gate outputs per phase (4 bits - S4 S3 S2 S1):
--!               "0011" → S1=ON,  S2=ON,  S3=OFF, S4=OFF → +Vdc/2 (POS)
--!               "0110" → S1=OFF, S2=ON,  S3=ON,  S4=OFF → 0 (NEUTRAL)
--!               "1100" → S1=OFF, S2=OFF, S3=ON,  S4=ON  → -Vdc/2 (NEG)
--------------------------------------------------------------------------
-- Standard libraries
--------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--------------------------------------------------------------------------
-- Entity declaration
--------------------------------------------------------------------------
Entity NPCManager is
    Generic (
        -- Modulator parameters
        CLK_FREQ         : natural := 100_000_000;  -- System clock frequency (Hz)
        PWM_FREQ         : natural := 20_000;       -- PWM switching frequency (Hz)
        DATA_WIDTH       : natural := 32;           -- Reference signal bit width
        LOAD_BOTH_EDGES  : boolean := false;        -- Sample at valley AND peak
        OUTPUT_REG       : boolean := true;         -- Add output register stage

        -- Gate driver parameters
        MIN_PULSE_WIDTH  : integer := 100;          -- Minimum pulse width (clock cycles)
        DEAD_TIME        : integer := 50;           -- Dead time (clock cycles)
        WAIT_STATE_CNT   : integer := 100000;       -- Wait state counter (~1ms at 100MHz)

        -- Output configuration
        INVERTED_PWM     : boolean := false         -- Invert PWM outputs
    );
    Port (
        sysclk      : in std_logic;
        reset_n     : in std_logic;

        --! PWM Enable (active high)
        --! Set to '0' to disable PWM and initiate safe shutdown
        pwm_enb_i   : in std_logic;

        --! Clear faults (active high pulse)
        clear_i     : in std_logic;

        --! Voltage references (signed fixed-point Q(DATA_WIDTH-1), normalized to ±1.0)
        va_ref_i    : in std_logic_vector(DATA_WIDTH-1 downto 0);
        vb_ref_i    : in std_logic_vector(DATA_WIDTH-1 downto 0);
        vc_ref_i    : in std_logic_vector(DATA_WIDTH-1 downto 0);

        --! Carrier synchronization tick (period start - use for control loop sync)
        carrier_tick_o : out std_logic;

        --! Reference sampling tick (valley and/or peak)
        sample_tick_o  : out std_logic;

        --! Gate outputs per phase (4 bits each: S4 S3 S2 S1)
        pwm_a_o     : out std_logic_vector(3 downto 0);
        pwm_b_o     : out std_logic_vector(3 downto 0);
        pwm_c_o     : out std_logic_vector(3 downto 0);

        --! PWM active feedback (all phases active)
        pwm_on_o    : out std_logic;

        --! Fault outputs
        fault_o     : out std_logic;        -- Latched fault (any phase)
        fs_fault_o  : out std_logic;        -- Forbidden state fault (pulse)
        minw_fault_o: out std_logic         -- Minimum pulse violation
    );
End entity;

--------------------------------------------------------------------------
-- Architecture
--------------------------------------------------------------------------
Architecture rtl of NPCManager is

    --------------------------------------------------------------------------
    -- Internal signals
    --------------------------------------------------------------------------
    -- Modulator outputs (NPC states)
    signal state_a          : std_logic_vector(1 downto 0);
    signal state_b          : std_logic_vector(1 downto 0);
    signal state_c          : std_logic_vector(1 downto 0);

    -- Carrier sync signal (used for enable synchronization)
    signal carrier_tick_int : std_logic;

    -- Gate driver outputs (before inversion)
    signal pwm_a_int        : std_logic_vector(3 downto 0);
    signal pwm_b_int        : std_logic_vector(3 downto 0);
    signal pwm_c_int        : std_logic_vector(3 downto 0);

    -- Fault signals (per phase)
    signal fault_int        : std_logic_vector(2 downto 0);
    signal fs_fault_int     : std_logic_vector(2 downto 0);
    signal minw_fault_int   : std_logic_vector(2 downto 0);

    -- PWM on feedback (per phase)
    signal pwm_on_int       : std_logic_vector(2 downto 0);

    -- Combined enable signal
    signal pwm_enable       : std_logic;

    -- Internal fault (any phase faulted)
    signal any_fault        : std_logic;

Begin

    --------------------------------------------------------------------------
    -- Fault detection (any phase)
    --------------------------------------------------------------------------
    any_fault <= fault_int(0) or fault_int(1) or fault_int(2);

    --------------------------------------------------------------------------
    -- PWM enable (directly from input - upper layer controls via pwm_enb_i)
    --------------------------------------------------------------------------
    pwm_enable <= pwm_enb_i;

    --------------------------------------------------------------------------
    -- Output assignments
    --------------------------------------------------------------------------
    -- Carrier tick output
    carrier_tick_o <= carrier_tick_int;

    -- PWM outputs (optionally inverted)
    pwm_a_o <= not pwm_a_int when INVERTED_PWM else pwm_a_int;
    pwm_b_o <= not pwm_b_int when INVERTED_PWM else pwm_b_int;
    pwm_c_o <= not pwm_c_int when INVERTED_PWM else pwm_c_int;

    -- Fault outputs (OR of all phases)
    fault_o      <= any_fault;
    fs_fault_o   <= fs_fault_int(0) or fs_fault_int(1) or fs_fault_int(2);
    minw_fault_o <= minw_fault_int(0) or minw_fault_int(1) or minw_fault_int(2);

    -- PWM on feedback (AND of all phases - all must be active)
    pwm_on_o <= pwm_on_int(0) and pwm_on_int(1) and pwm_on_int(2);

    --------------------------------------------------------------------------
    -- NPCModulator Instantiation
    --------------------------------------------------------------------------
    Modulator: entity work.NPCModulator
    generic map (
        CLK_FREQ        => CLK_FREQ,
        PWM_FREQ        => PWM_FREQ,
        DATA_WIDTH      => DATA_WIDTH,
        LOAD_BOTH_EDGES => LOAD_BOTH_EDGES,
        OUTPUT_REG      => OUTPUT_REG
    )
    port map (
        sysclk         => sysclk,
        reset_n        => reset_n,
        -- Voltage references
        va_ref_i       => va_ref_i,
        vb_ref_i       => vb_ref_i,
        vc_ref_i       => vc_ref_i,
        -- Carrier synchronization
        carrier_tick_o => carrier_tick_int,
        sample_tick_o  => sample_tick_o,
        -- NPC state outputs
        state_a_o      => state_a,
        state_b_o      => state_b,
        state_c_o      => state_c
    );

    --------------------------------------------------------------------------
    -- NPCGateDriver Instantiation (3 phases)
    --------------------------------------------------------------------------
    -- Phase A
    GateDriver_A: entity work.NPCGateDriver
    generic map (
        MIN_PULSE_WIDTH => MIN_PULSE_WIDTH,
        DEAD_TIME       => DEAD_TIME,
        WAIT_STATE_CNT  => WAIT_STATE_CNT
    )
    port map (
        sysclk      => sysclk,
        reset_n     => reset_n,
        -- Control interface
        en_i        => pwm_enable,
        sync_i      => carrier_tick_int,
        clear_i     => clear_i,
        -- NPC state input
        state_i     => state_a,
        -- Gate outputs
        pwm_o       => pwm_a_int,
        -- Status/Fault outputs
        min_fault_o => minw_fault_int(0),
        fs_fault_o  => fs_fault_int(0),
        fault_o     => fault_int(0),
        pwm_on_o    => pwm_on_int(0)
    );

    -- Phase B
    GateDriver_B: entity work.NPCGateDriver
    generic map (
        MIN_PULSE_WIDTH => MIN_PULSE_WIDTH,
        DEAD_TIME       => DEAD_TIME,
        WAIT_STATE_CNT  => WAIT_STATE_CNT
    )
    port map (
        sysclk      => sysclk,
        reset_n     => reset_n,
        -- Control interface
        en_i        => pwm_enable,
        sync_i      => carrier_tick_int,
        clear_i     => clear_i,
        -- NPC state input
        state_i     => state_b,
        -- Gate outputs
        pwm_o       => pwm_b_int,
        -- Status/Fault outputs
        min_fault_o => minw_fault_int(1),
        fs_fault_o  => fs_fault_int(1),
        fault_o     => fault_int(1),
        pwm_on_o    => pwm_on_int(1)
    );

    -- Phase C
    GateDriver_C: entity work.NPCGateDriver
    generic map (
        MIN_PULSE_WIDTH => MIN_PULSE_WIDTH,
        DEAD_TIME       => DEAD_TIME,
        WAIT_STATE_CNT  => WAIT_STATE_CNT
    )
    port map (
        sysclk      => sysclk,
        reset_n     => reset_n,
        -- Control interface
        en_i        => pwm_enable,
        sync_i      => carrier_tick_int,
        clear_i     => clear_i,
        -- NPC state input
        state_i     => state_c,
        -- Gate outputs
        pwm_o       => pwm_c_int,
        -- Status/Fault outputs
        min_fault_o => minw_fault_int(2),
        fs_fault_o  => fs_fault_int(2),
        fault_o     => fault_int(2),
        pwm_on_o    => pwm_on_int(2)
    );

End architecture;
