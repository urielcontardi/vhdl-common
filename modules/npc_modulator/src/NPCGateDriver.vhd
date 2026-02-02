--! \file       NPCGateDriver.vhd
--!
--! \brief      NPC Gate Driver with safe state transitions, dead time,
--!             minimum pulse width, and ordered shutdown sequence.
--!
--! \author     Uriel Abe Contardi (urielcontardi@hotmail.com)
--! \date       01-02-2026
--!
--! \version    2.0
--!
--! \copyright  Copyright (c) 2026 - All Rights reserved.
--!
--! \details    Receives 2-bit NPC states from NPCModulator and ensures:
--!             - Valid state transitions (must pass through neutral)
--!             - Dead time between complementary switches
--!             - Minimum pulse width enforcement
--!             - Safe shutdown sequence with wait state
--!
--!             NPC State inputs (2 bits):
--!               "11" = POS, "01" = NEUTRAL, "00" = NEG
--!
--!             Gate output vectors (4 bits - S4 S3 S2 S1):
--!               "0011" → S1=ON,  S2=ON,  S3=OFF, S4=OFF → +Vdc/2 (POS)
--!               "0110" → S1=OFF, S2=ON,  S3=ON,  S4=OFF → 0 (NEUTRAL)
--!               "1100" → S1=OFF, S2=OFF, S3=ON,  S4=ON  → -Vdc/2 (NEG)
--!
--!             Valid transitions: POS ↔ NEUTRAL ↔ NEG (never skip neutral)
--------------------------------------------------------------------------
-- Standard libraries
--------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--------------------------------------------------------------------------
-- Entity declaration
--------------------------------------------------------------------------
Entity NPCGateDriver is
    Generic (
        MIN_PULSE_WIDTH : integer := 100;   -- Minimum pulse width in clock cycles
        DEAD_TIME       : integer := 50;    -- Dead time in clock cycles
        WAIT_STATE_CNT  : integer := 100000 -- Wait state counter (~1ms at 100MHz)
    );
    Port (
        sysclk      : in std_logic;
        reset_n     : in std_logic;

        --! Control interface
        en_i        : in std_logic;         -- PWM enable
        sync_i      : in std_logic;         -- Sync pulse (from carrier valley)
        clear_i     : in std_logic;         -- Clear faults

        --! NPC state input (from NPCModulator) - 2 bits per phase
        --! "11" = POS, "01" = NEUTRAL, "00" = NEG
        state_i     : in std_logic_vector(1 downto 0);

        --! Gate outputs (directly to drivers)
        pwm_o       : out std_logic_vector(3 downto 0);

        --! Status/Fault outputs
        min_fault_o : out std_logic;        -- Min pulse violation
        fs_fault_o  : out std_logic;        -- Forbidden state pulse (1 clk)
        fault_o     : out std_logic;        -- Latched fault flag
        pwm_on_o    : out std_logic         -- PWM is active (not OFF)
    );
End entity;

--------------------------------------------------------------------------
-- Architecture
--------------------------------------------------------------------------
Architecture rtl of NPCGateDriver is

    --------------------------------------------------------------------------
    -- Functions
    --------------------------------------------------------------------------
    function Max(int0 : integer; int1 : integer) return integer is
    begin
        if int0 > int1 then
            return int0;
        else
            return int1;
        end if;
    end function;

    --------------------------------------------------------------------------
    -- Constants
    --------------------------------------------------------------------------
    -- NPC State inputs (2 bits from modulator)
    constant ST_POS_IN  : std_logic_vector(1 downto 0) := "11";  -- Positive
    constant ST_ZERO_IN : std_logic_vector(1 downto 0) := "01";  -- Neutral
    constant ST_NEG_IN  : std_logic_vector(1 downto 0) := "00";  -- Negative

    -- Gate output vectors (4 bits to drivers)
    constant VEC_POS    : std_logic_vector(3 downto 0) := "0011";  -- S1=1, S2=1
    constant VEC_ZERO_P : std_logic_vector(3 downto 0) := "0010";  -- S2=1 only (from POS)
    constant VEC_NEG    : std_logic_vector(3 downto 0) := "1100";  -- S3=1, S4=1
    constant VEC_ZERO_N : std_logic_vector(3 downto 0) := "0100";  -- S3=1 only (from NEG)
    constant VEC_ZERO   : std_logic_vector(3 downto 0) := "0110";  -- S2=1, S3=1 (NEUTRAL)
    constant VEC_OFF    : std_logic_vector(3 downto 0) := "0000";  -- All OFF

    --------------------------------------------------------------------------
    -- Types
    --------------------------------------------------------------------------
    type fsm_state_t is (ST_POS, ST_POS_DEAD, ST_ZERO, ST_NEG, ST_NEG_DEAD, ST_OFF, WAIT_ST);

    --------------------------------------------------------------------------
    -- Signals
    --------------------------------------------------------------------------
    -- FSM state
    signal state            : fsm_state_t := ST_OFF;
    signal state_next       : fsm_state_t;
    signal state_last       : fsm_state_t := ST_OFF;

    -- PWM output register
    signal pwm              : std_logic_vector(3 downto 0) := (others => '0');
    signal pwm_next         : std_logic_vector(3 downto 0);

    -- Input latching
    signal state_i_last     : std_logic_vector(1 downto 0) := (others => '0');

    -- Counters
    signal ctr              : integer range 0 to Max(MIN_PULSE_WIDTH, DEAD_TIME) := 0;
    signal ctr_next         : integer range 0 to Max(MIN_PULSE_WIDTH, DEAD_TIME);
    signal ctr_wait         : integer range 0 to WAIT_STATE_CNT - 1 := 0;
    signal ctr_wait_next    : integer range 0 to WAIT_STATE_CNT - 1;

    -- Timing flags
    signal minw_ok          : std_logic := '0';
    signal minw_ok_next     : std_logic;
    signal dt_ok            : std_logic := '0';
    signal dt_ok_next       : std_logic;
    signal dt_ok_reg        : std_logic := '0';
    signal dt_ok_redge      : std_logic := '0';

    -- Faults
    signal fault            : std_logic := '0';
    signal fault_next       : std_logic;
    signal forb_state       : std_logic := '0';
    signal forb_state_next  : std_logic;
    signal min_fault        : std_logic := '0';
    signal min_fault_next   : std_logic;

    -- Enable synchronized
    signal en_sync          : std_logic := '0';
    signal en_sync_next     : std_logic;

Begin

    --------------------------------------------------------------------------
    -- Output assignments
    --------------------------------------------------------------------------
    pwm_o       <= pwm;
    min_fault_o <= min_fault;
    fs_fault_o  <= forb_state;
    fault_o     <= fault;
    pwm_on_o    <= '0' when (state = ST_OFF) else '1';

    --------------------------------------------------------------------------
    -- Internal signals
    --------------------------------------------------------------------------
    dt_ok_redge <= dt_ok and not dt_ok_reg;

    --------------------------------------------------------------------------
    -- Sequential process
    --------------------------------------------------------------------------
    seq_proc : process(sysclk, reset_n)
    begin
        if reset_n = '0' then
            state        <= ST_OFF;
            state_last   <= ST_OFF;
            state_i_last <= (others => '0');
            pwm          <= (others => '0');
            ctr          <= 0;
            ctr_wait     <= 0;
            minw_ok      <= '0';
            dt_ok        <= '0';
            dt_ok_reg    <= '0';
            fault        <= '0';
            forb_state   <= '0';
            min_fault    <= '0';
            en_sync      <= '0';
        elsif rising_edge(sysclk) then
            state        <= state_next;
            state_last   <= state;
            state_i_last <= state_i;
            pwm          <= pwm_next;
            ctr          <= ctr_next;
            ctr_wait     <= ctr_wait_next;
            minw_ok      <= minw_ok_next;
            dt_ok        <= dt_ok_next;
            dt_ok_reg    <= dt_ok;
            fault        <= fault_next;
            forb_state   <= forb_state_next;
            min_fault    <= min_fault_next;
            en_sync      <= en_sync_next;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- Combinational process
    --------------------------------------------------------------------------
    comb_proc : process(state, state_last, pwm, ctr, ctr_wait, minw_ok, dt_ok,
                        dt_ok_redge, fault, forb_state, min_fault, en_sync,
                        sync_i, clear_i, state_i, state_i_last, en_i)
    begin
        -- Default: hold current values (prevent latch)
        state_next      <= state;
        pwm_next        <= pwm;
        ctr_next        <= ctr;
        ctr_wait_next   <= ctr_wait;
        minw_ok_next    <= minw_ok;
        dt_ok_next      <= dt_ok;
        fault_next      <= fault;
        forb_state_next <= '0';
        min_fault_next  <= '0';
        en_sync_next    <= en_sync;

        -- Sync Enable command
        if sync_i = '1' then
            en_sync_next <= en_i;
        end if;

        ------------------------------------------------------------------------
        -- FSM: State transitions
        ------------------------------------------------------------------------
        case state is

            ----------------------------------------------------------------
            -- OFF: All gates disabled
            ----------------------------------------------------------------
            when ST_OFF =>
                pwm_next <= VEC_OFF;

                -- Safe StartUp: require transition TO ZERO (neutral)
                if (en_sync = '1') and (fault = '0') and 
                   (state_i = ST_ZERO_IN) and (state_i_last /= ST_ZERO_IN) then
                    state_next <= ST_ZERO;
                end if;

            ----------------------------------------------------------------
            -- POS: Positive state (+Vdc/2)
            ----------------------------------------------------------------
            when ST_POS =>
                pwm_next <= VEC_POS;

                if minw_ok = '1' then
                    if state_i = ST_POS_IN then
                        state_next <= state;
                    elsif state_i = ST_ZERO_IN then
                        state_next <= ST_POS_DEAD;
                    elsif state_i = ST_NEG_IN then
                        -- Force transition through NEUTRAL (POS → ZERO → NEG)
                        state_next <= ST_POS_DEAD;
                    end if;
                end if;

            ----------------------------------------------------------------
            -- POS_DEAD: Dead time POS → NEUTRAL
            ----------------------------------------------------------------
            when ST_POS_DEAD =>
                pwm_next <= VEC_ZERO_P;

                if dt_ok_redge = '1' then
                    if state_i = ST_POS_IN then
                        state_next <= ST_POS;
                    else
                        state_next <= ST_ZERO;
                    end if;
                end if;

            ----------------------------------------------------------------
            -- ZERO (NEUTRAL): 0V
            ----------------------------------------------------------------
            when ST_ZERO =>
                pwm_next <= VEC_ZERO;

                if minw_ok = '1' then
                    if state_i = ST_ZERO_IN then
                        state_next <= state;
                    elsif state_i = ST_POS_IN then
                        -- ZERO → POS: turn off S3 first, then turn on S1
                        state_next <= ST_POS_DEAD;
                    elsif state_i = ST_NEG_IN then
                        -- ZERO → NEG: turn off S2 first, then turn on S4
                        state_next <= ST_NEG_DEAD;
                    end if;
                    -- Note: state_i = "10" is undefined, ignore it
                end if;

            ----------------------------------------------------------------
            -- NEG_DEAD: Dead time NEUTRAL ↔ NEG
            ----------------------------------------------------------------
            when ST_NEG_DEAD =>
                pwm_next <= VEC_ZERO_N;

                if dt_ok_redge = '1' then
                    if state_i = ST_NEG_IN then
                        state_next <= ST_NEG;
                    else
                        state_next <= ST_ZERO;
                    end if;
                end if;

            ----------------------------------------------------------------
            -- NEG: Negative state (-Vdc/2)
            ----------------------------------------------------------------
            when ST_NEG =>
                pwm_next <= VEC_NEG;

                if minw_ok = '1' then
                    if state_i = ST_NEG_IN then
                        state_next <= state;
                    elsif state_i = ST_ZERO_IN then
                        state_next <= ST_NEG_DEAD;
                    elsif state_i = ST_POS_IN then
                        -- Force transition through NEUTRAL (NEG → ZERO → POS)
                        state_next <= ST_NEG_DEAD;
                    end if;
                end if;

            ----------------------------------------------------------------
            -- WAIT_ST: Wait state before returning to OFF
            ----------------------------------------------------------------
            when WAIT_ST =>
                pwm_next <= VEC_OFF;

                -- Wait for enable to be low before counting
                if en_i = '0' then
                    if ctr_wait < WAIT_STATE_CNT - 1 then
                        ctr_wait_next <= ctr_wait + 1;
                    else
                        ctr_wait_next <= 0;
                        state_next    <= ST_OFF;
                    end if;
                end if;

        end case;

        ------------------------------------------------------------------------
        -- TurnOff Sequence (priority over normal operation)
        ------------------------------------------------------------------------
        if (en_i = '0' or fault = '1') and (state /= ST_OFF) and (state /= WAIT_ST) then
            -- Hold current state
            state_next      <= state;
            forb_state_next <= '0';

            -- Wait Min Width before transitioning
            if minw_ok = '1' then
                if pwm = VEC_POS then
                    state_next <= ST_POS_DEAD;
                elsif pwm = VEC_ZERO then
                    state_next <= ST_OFF;
                elsif pwm = VEC_NEG then
                    state_next <= ST_NEG_DEAD;
                end if;
            end if;

            -- Wait Dead Time for each intermediate state
            if dt_ok_redge = '1' then
                if pwm = VEC_ZERO_N or pwm = VEC_ZERO_P then
                    state_next <= WAIT_ST;
                end if;
            end if;
        end if;

        ------------------------------------------------------------------------
        -- Min Width and Dead Time Counter
        ------------------------------------------------------------------------
        -- Dead Time Ok
        if ctr >= DEAD_TIME - 1 then
            dt_ok_next <= '1';
        end if;

        -- Min Pulse Ok
        if ctr >= MIN_PULSE_WIDTH - 1 then
            minw_ok_next <= '1';
        end if;

        -- Counter: reset on state change, otherwise increment
        if state_last /= state then
            ctr_next     <= 0;
            minw_ok_next <= '0';
            dt_ok_next   <= '0';
        elsif ctr < Max(MIN_PULSE_WIDTH, DEAD_TIME) then
            ctr_next <= ctr + 1;
        end if;

        ------------------------------------------------------------------------
        -- Clear fault
        ------------------------------------------------------------------------
        if clear_i = '1' then
            fault_next <= '0';
        end if;

    end process;

End architecture;
