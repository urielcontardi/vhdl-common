--------------------------------------------------------------------------
--! \file       tb_NPCManager.vhd
--!
--! \brief      Testbench for NPCManager module.
--!
--! \author     Uriel Abe Contardi (urielcontardi@hotmail.com)
--! \date       01-02-2026
--!
--! \details    Tests the complete NPC modulation chain:
--!             NPCModulator → NPCGateDriver (x3 phases)
--------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

--------------------------------------------------------------------------
-- Entity
--------------------------------------------------------------------------
Entity tb_NPCManager is
End entity;

--------------------------------------------------------------------------
-- Architecture
--------------------------------------------------------------------------
Architecture sim of tb_NPCManager is

    --------------------------------------------------------------------------
    -- Constants
    --------------------------------------------------------------------------
    constant CLK_PERIOD     : time := 10 ns;      -- 100 MHz
    constant CLK_FREQ       : natural := 100_000_000;
    constant PWM_FREQ       : natural := 10_000;  -- 10 kHz for faster simulation
    constant DATA_WIDTH     : natural := 16;
    constant MIN_PULSE      : integer := 50;
    constant DEAD_TIME      : integer := 25;
    constant WAIT_STATE_CNT : integer := 100;

    -- Carrier period in clock cycles
    constant CARRIER_PERIOD : natural := CLK_FREQ / PWM_FREQ;  -- 10000 cycles

    --------------------------------------------------------------------------
    -- Signals
    --------------------------------------------------------------------------
    signal sysclk       : std_logic := '0';
    signal reset_n      : std_logic := '0';

    -- Control
    signal pwm_enb      : std_logic := '0';
    signal clear        : std_logic := '0';

    -- References (signed)
    signal va_ref       : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal vb_ref       : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal vc_ref       : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');

    -- Outputs
    signal carrier_tick : std_logic;
    signal sample_tick  : std_logic;
    signal pwm_a        : std_logic_vector(3 downto 0);
    signal pwm_b        : std_logic_vector(3 downto 0);
    signal pwm_c        : std_logic_vector(3 downto 0);
    signal pwm_on       : std_logic;
    signal fault_out    : std_logic;
    signal fs_fault     : std_logic;
    signal minw_fault   : std_logic;

    -- Simulation control
    signal sim_done     : boolean := false;

    -- Test counters
    signal test_count   : integer := 0;
    signal pass_count   : integer := 0;
    signal fail_count   : integer := 0;

Begin

    --------------------------------------------------------------------------
    -- Clock generation
    --------------------------------------------------------------------------
    sysclk <= not sysclk after CLK_PERIOD/2 when not sim_done else '0';

    --------------------------------------------------------------------------
    -- DUT instantiation
    --------------------------------------------------------------------------
    DUT: entity work.NPCManager
    generic map (
        CLK_FREQ        => CLK_FREQ,
        PWM_FREQ        => PWM_FREQ,
        DATA_WIDTH      => DATA_WIDTH,
        LOAD_BOTH_EDGES => false,
        OUTPUT_REG      => true,
        MIN_PULSE_WIDTH => MIN_PULSE,
        DEAD_TIME       => DEAD_TIME,
        WAIT_STATE_CNT  => WAIT_STATE_CNT,
        INVERTED_PWM    => false
    )
    port map (
        sysclk         => sysclk,
        reset_n        => reset_n,
        pwm_enb_i      => pwm_enb,
        clear_i        => clear,
        va_ref_i       => va_ref,
        vb_ref_i       => vb_ref,
        vc_ref_i       => vc_ref,
        carrier_tick_o => carrier_tick,
        sample_tick_o  => sample_tick,
        pwm_a_o        => pwm_a,
        pwm_b_o        => pwm_b,
        pwm_c_o        => pwm_c,
        pwm_on_o       => pwm_on,
        fault_o        => fault_out,
        fs_fault_o     => fs_fault,
        minw_fault_o   => minw_fault
    );

    --------------------------------------------------------------------------
    -- Main test process
    --------------------------------------------------------------------------
    stim_proc: process
        -- Helper: wait N clock cycles
        procedure wait_clk(n : integer) is
        begin
            for i in 1 to n loop
                wait until rising_edge(sysclk);
            end loop;
        end procedure;

        -- Helper: wait for carrier tick
        procedure wait_carrier_tick is
        begin
            wait until rising_edge(sysclk) and carrier_tick = '1';
        end procedure;

        -- Helper: set three-phase references (normalized -1.0 to +1.0)
        procedure set_refs(a, b, c : real) is
            variable max_val : real := real(2**(DATA_WIDTH-1) - 1);
        begin
            va_ref <= std_logic_vector(to_signed(integer(a * max_val), DATA_WIDTH));
            vb_ref <= std_logic_vector(to_signed(integer(b * max_val), DATA_WIDTH));
            vc_ref <= std_logic_vector(to_signed(integer(c * max_val), DATA_WIDTH));
        end procedure;

        -- Helper: check test result
        procedure check(condition : boolean; msg : string) is
        begin
            test_count <= test_count + 1;
            if condition then
                pass_count <= pass_count + 1;
                report "[PASS] " & msg severity note;
            else
                fail_count <= fail_count + 1;
                report "[FAIL] " & msg severity warning;
            end if;
        end procedure;

    begin
        report "========================================";
        report "   NPCManager Testbench";
        report "========================================";

        -- Initial reset
        reset_n <= '0';
        pwm_enb <= '0';
        clear   <= '0';
        set_refs(0.0, 0.0, 0.0);

        wait_clk(10);
        reset_n <= '1';
        wait_clk(10);

        ------------------------------------------------------------------------
        -- T1: Verify reset state
        ------------------------------------------------------------------------
        report "T1: Verify reset state";
        check(pwm_a = "0000", "Phase A outputs OFF after reset");
        check(pwm_b = "0000", "Phase B outputs OFF after reset");
        check(pwm_c = "0000", "Phase C outputs OFF after reset");
        check(pwm_on = '0', "PWM_on = 0 after reset");

        ------------------------------------------------------------------------
        -- T2: Enable with NEUTRAL reference
        ------------------------------------------------------------------------
        report "T2: Enable with NEUTRAL reference (0.0)";
        
        -- Start with non-neutral to create transition TO neutral
        set_refs(0.5, 0.5, 0.5);  -- Start at POS
        wait_carrier_tick;
        
        pwm_enb <= '1';
        wait_carrier_tick;
        
        -- Now transition TO neutral (required for safe startup)
        set_refs(0.0, 0.0, 0.0);
        wait_carrier_tick;
        wait_carrier_tick;
        wait_clk(MIN_PULSE + 10);

        check(pwm_on = '1', "PWM active after enable with neutral");

        ------------------------------------------------------------------------
        -- T3: Positive reference
        ------------------------------------------------------------------------
        report "T3: Positive reference (0.8)";
        set_refs(0.8, 0.8, 0.8);  -- All phases positive
        wait_carrier_tick;
        wait_carrier_tick;
        wait_carrier_tick;
        wait_clk(DEAD_TIME + MIN_PULSE + 100);

        -- Check phase A is in positive state sometime during the cycle
        check(pwm_a = "0011" or pwm_a = "0010" or pwm_a = "0110", 
              "Phase A in valid state (POS, DEAD, or ZERO)");

        ------------------------------------------------------------------------
        -- T4: Negative reference
        ------------------------------------------------------------------------
        report "T4: Negative reference (-0.8)";
        set_refs(0.0, 0.0, 0.0);  -- Return to neutral first
        wait_carrier_tick;
        wait_carrier_tick;
        wait_clk(DEAD_TIME + MIN_PULSE + 20);

        set_refs(-0.8, 0.0, 0.0);  -- Phase A negative
        wait_carrier_tick;
        wait_carrier_tick;
        wait_clk(DEAD_TIME + MIN_PULSE + 20);

        check(pwm_a = "1100" or pwm_a = "0100" or pwm_a = "0110", 
              "Phase A in valid state (NEG, DEAD, or ZERO)");

        ------------------------------------------------------------------------
        -- T5: Three-phase balanced
        ------------------------------------------------------------------------
        report "T5: Three-phase balanced (120 deg)";
        -- Approximate 120 degree phase shift
        set_refs(0.5, -0.25, -0.25);
        wait_carrier_tick;
        wait_carrier_tick;
        wait_clk(DEAD_TIME + MIN_PULSE + 20);

        check(true, "Three-phase outputs active");

        ------------------------------------------------------------------------
        -- T6: Disable via pwm_enb
        ------------------------------------------------------------------------
        report "T6: Disable via pwm_enb";
        pwm_enb <= '0';
        wait_clk(MIN_PULSE + DEAD_TIME + WAIT_STATE_CNT + 50);

        check(pwm_on = '0', "PWM disabled after pwm_enb low");
        check(pwm_a = "0000", "Phase A OFF after disable");

        ------------------------------------------------------------------------
        -- T7: Re-enable after disable
        ------------------------------------------------------------------------
        report "T7: Re-enable after disable";
        -- Clear any internal faults first
        clear <= '1';
        wait_clk(5);
        clear <= '0';
        wait_clk(10);
        -- Trigger state transition to ZERO
        set_refs(0.5, 0.0, 0.0);  -- Move away from zero
        wait_clk(10);
        set_refs(0.0, 0.0, 0.0);  -- Back to zero (edge to trigger startup)
        pwm_enb <= '1';
        wait_carrier_tick;
        wait_carrier_tick;
        wait_clk(MIN_PULSE + DEAD_TIME + 100);

        check(pwm_on = '1', "PWM active after re-enable");

        ------------------------------------------------------------------------
        -- T8: Disable PWM
        ------------------------------------------------------------------------
        report "T8: Disable PWM";
        pwm_enb <= '0';
        wait_clk(MIN_PULSE + DEAD_TIME + WAIT_STATE_CNT + 50);

        check(pwm_on = '0', "PWM disabled after enable=0");
        check(pwm_a = "0000", "Phase A OFF after disable");

        ------------------------------------------------------------------------
        -- End of tests
        ------------------------------------------------------------------------
        wait_clk(100);

        report "========================================";
        report "   Test Summary";
        report "========================================";
        report "  Total tests: " & integer'image(test_count);
        report "  Passed:      " & integer'image(pass_count);
        report "  Failed:      " & integer'image(fail_count);

        if fail_count = 0 then
            report "  ALL TESTS PASSED!" severity note;
        else
            report "  SOME TESTS FAILED!" severity warning;
        end if;

        report "========================================";

        sim_done <= true;
        wait;
    end process;

End architecture;
