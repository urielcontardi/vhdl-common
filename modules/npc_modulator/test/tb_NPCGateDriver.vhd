--! \file       tb_NPCGateDriver.vhd
--!
--! \brief      Testbench for NPCGateDriver module.
--!
--! \author     Uriel Abe Contardi (urielcontardi@hotmail.com)
--! \date       01-02-2026
--!
--! \version    1.0
--!
--! \copyright  Copyright (c) 2026 - All Rights reserved.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_NPCGateDriver is
end entity;

architecture sim of tb_NPCGateDriver is

    --------------------------------------------------------------------------
    -- Constants
    --------------------------------------------------------------------------
    constant CLK_PERIOD     : time := 10 ns;
    constant MIN_PULSE      : integer := 100;
    constant DEAD_TIME      : integer := 50;
    constant WAIT_STATE_CNT : integer := 1000;

    -- NPC State inputs (2 bits)
    constant ST_POS_IN  : std_logic_vector(1 downto 0) := "11";
    constant ST_ZERO_IN : std_logic_vector(1 downto 0) := "01";
    constant ST_NEG_IN  : std_logic_vector(1 downto 0) := "00";

    -- Gate output patterns (4 bits)
    constant VEC_OFF     : std_logic_vector(3 downto 0) := "0000";
    constant VEC_POS     : std_logic_vector(3 downto 0) := "0011";
    constant VEC_ZERO_P  : std_logic_vector(3 downto 0) := "0010";
    constant VEC_ZERO    : std_logic_vector(3 downto 0) := "0110";
    constant VEC_ZERO_N  : std_logic_vector(3 downto 0) := "0100";
    constant VEC_NEG     : std_logic_vector(3 downto 0) := "1100";

    --------------------------------------------------------------------------
    -- Signals
    --------------------------------------------------------------------------
    signal sysclk       : std_logic := '0';
    signal reset_n      : std_logic := '0';
    signal en_i         : std_logic := '0';
    signal sync_i       : std_logic := '0';
    signal clear_i      : std_logic := '0';
    signal state_i      : std_logic_vector(1 downto 0) := ST_ZERO_IN;
    signal pwm_o        : std_logic_vector(3 downto 0);
    signal min_fault_o  : std_logic;
    signal fs_fault_o   : std_logic;
    signal fault_o      : std_logic;
    signal pwm_on_o     : std_logic;

    signal test_done    : boolean := false;
    signal test_pass    : integer := 0;
    signal test_fail    : integer := 0;

begin

    sysclk <= not sysclk after CLK_PERIOD / 2 when not test_done else '0';

    dut: entity work.NPCGateDriver
        generic map (
            MIN_PULSE_WIDTH => MIN_PULSE,
            DEAD_TIME       => DEAD_TIME,
            WAIT_STATE_CNT  => WAIT_STATE_CNT
        )
        port map (
            sysclk      => sysclk,
            reset_n     => reset_n,
            en_i        => en_i,
            sync_i      => sync_i,
            clear_i     => clear_i,
            state_i     => state_i,
            pwm_o       => pwm_o,
            min_fault_o => min_fault_o,
            fs_fault_o  => fs_fault_o,
            fault_o     => fault_o,
            pwm_on_o    => pwm_on_o
        );

    --------------------------------------------------------------------------
    -- Main test process
    --------------------------------------------------------------------------
    process
        procedure do_sync is
        begin
            wait until rising_edge(sysclk);
            sync_i <= '1';
            wait until rising_edge(sysclk);
            sync_i <= '0';
        end procedure;

        procedure wait_cycles(n : natural) is
        begin
            for i in 1 to n loop
                wait until rising_edge(sysclk);
            end loop;
        end procedure;

        procedure wait_us(n : natural) is
        begin
            wait for n * 1 us;
        end procedure;

        procedure check(name : string; condition : boolean) is
        begin
            if condition then
                report "[PASS] " & name;
                test_pass <= test_pass + 1;
            else
                report "[FAIL] " & name severity error;
                test_fail <= test_fail + 1;
            end if;
        end procedure;

        procedure do_reset is
        begin
            reset_n <= '0';
            en_i <= '0';
            state_i <= ST_ZERO_IN;
            wait for 100 ns;
            reset_n <= '1';
            wait_cycles(5);
        end procedure;

        procedure startup is
        begin
            state_i <= ST_POS_IN;
            wait_cycles(5);
            en_i <= '1';
            do_sync;
            wait_cycles(5);
            state_i <= ST_ZERO_IN;
            do_sync;
            wait_us(2);
        end procedure;

    begin
        report "========================================";
        report "       NPCGateDriver Testbench";
        report "========================================";

        ------------------------------------------------------------------------
        -- TEST 1: Reset state
        ------------------------------------------------------------------------
        do_reset;
        check("T1.1 - Reset: pwm_o = OFF", pwm_o = VEC_OFF);
        check("T1.2 - Reset: pwm_on_o = 0", pwm_on_o = '0');
        check("T1.3 - Reset: fault = 0", fault_o = '0');

        ------------------------------------------------------------------------
        -- TEST 2: Block startup with POS
        ------------------------------------------------------------------------
        state_i <= ST_POS_IN;
        en_i <= '1';
        do_sync;
        wait_us(1);
        check("T2.1 - Block startup with POS", pwm_o = VEC_OFF);

        ------------------------------------------------------------------------
        -- TEST 3: Block startup with NEG
        ------------------------------------------------------------------------
        do_reset;
        state_i <= ST_NEG_IN;
        en_i <= '1';
        do_sync;
        wait_us(1);
        check("T3.1 - Block startup with NEG", pwm_o = VEC_OFF);

        ------------------------------------------------------------------------
        -- TEST 4: Valid startup with ZERO transition
        ------------------------------------------------------------------------
        do_reset;
        startup;
        check("T4.1 - Valid startup: pwm_o = ZERO", pwm_o = VEC_ZERO);
        check("T4.2 - Valid startup: pwm_on_o = 1", pwm_on_o = '1');

        ------------------------------------------------------------------------
        -- TEST 5: Transition ZERO -> POS
        ------------------------------------------------------------------------
        state_i <= ST_POS_IN;
        do_sync;
        wait_us(2);
        check("T5.1 - ZERO to POS transition", pwm_o = VEC_POS);

        ------------------------------------------------------------------------
        -- TEST 6: Transition POS -> ZERO
        ------------------------------------------------------------------------
        state_i <= ST_ZERO_IN;
        do_sync;
        wait_us(2);
        check("T6.1 - POS to ZERO transition", pwm_o = VEC_ZERO);

        ------------------------------------------------------------------------
        -- TEST 7: Transition ZERO -> NEG
        ------------------------------------------------------------------------
        state_i <= ST_NEG_IN;
        do_sync;
        wait_us(2);
        check("T7.1 - ZERO to NEG transition", pwm_o = VEC_NEG);

        ------------------------------------------------------------------------
        -- TEST 8: Transition NEG -> ZERO
        ------------------------------------------------------------------------
        state_i <= ST_ZERO_IN;
        do_sync;
        wait_us(2);
        check("T8.1 - NEG to ZERO transition", pwm_o = VEC_ZERO);

        ------------------------------------------------------------------------
        -- TEST 9: Forbidden transition POS -> NEG (fault)
        ------------------------------------------------------------------------
        do_reset;
        startup;
        state_i <= ST_POS_IN;
        do_sync;
        wait_us(2);
        state_i <= ST_NEG_IN;
        do_sync;
        wait_us(2);
        check("T9.1 - Forbidden POS to NEG: fault = 1", fault_o = '1');

        -- Clear fault
        clear_i <= '1';
        wait_cycles(5);
        clear_i <= '0';
        wait_cycles(5);
        check("T9.2 - Clear fault", fault_o = '0');

        ------------------------------------------------------------------------
        -- TEST 10: Forbidden transition NEG -> POS (fault)
        ------------------------------------------------------------------------
        do_reset;
        startup;
        state_i <= ST_NEG_IN;
        do_sync;
        wait_us(2);
        state_i <= ST_POS_IN;
        do_sync;
        wait_us(2);
        check("T10.1 - Forbidden NEG to POS: fault = 1", fault_o = '1');

        clear_i <= '1';
        wait_cycles(5);
        clear_i <= '0';

        ------------------------------------------------------------------------
        -- TEST 11: Shutdown from POS
        ------------------------------------------------------------------------
        do_reset;
        startup;
        state_i <= ST_POS_IN;
        do_sync;
        wait_us(2);
        check("T11.1 - In POS before shutdown", pwm_o = VEC_POS);
        
        en_i <= '0';
        do_sync;
        wait for 20 us;
        check("T11.2 - Shutdown from POS: pwm_o = OFF", pwm_o = VEC_OFF);
        check("T11.3 - Shutdown from POS: pwm_on_o = 0", pwm_on_o = '0');

        ------------------------------------------------------------------------
        -- TEST 12: Shutdown from NEG
        ------------------------------------------------------------------------
        do_reset;
        startup;
        state_i <= ST_NEG_IN;
        do_sync;
        wait_us(2);
        check("T12.1 - In NEG before shutdown", pwm_o = VEC_NEG);
        
        en_i <= '0';
        do_sync;
        wait for 20 us;
        check("T12.2 - Shutdown from NEG: pwm_o = OFF", pwm_o = VEC_OFF);
        check("T12.3 - Shutdown from NEG: pwm_on_o = 0", pwm_on_o = '0');

        ------------------------------------------------------------------------
        -- TEST 13: Shutdown from ZERO (direct)
        ------------------------------------------------------------------------
        do_reset;
        startup;
        check("T13.1 - In ZERO before shutdown", pwm_o = VEC_ZERO);
        
        en_i <= '0';
        do_sync;
        wait for 20 us;
        check("T13.2 - Shutdown from ZERO: pwm_o = OFF", pwm_o = VEC_OFF);

        ------------------------------------------------------------------------
        -- TEST 14: Dead time insertion (ZERO -> POS)
        ------------------------------------------------------------------------
        do_reset;
        startup;
        state_i <= ST_POS_IN;
        do_sync;
        wait_cycles(10);  -- Less than dead time
        check("T14.1 - Dead time: ZERO_P during transition", pwm_o = VEC_ZERO_P);
        wait_us(2);
        check("T14.2 - Dead time: POS after transition", pwm_o = VEC_POS);

        ------------------------------------------------------------------------
        -- TEST 15: Dead time insertion (ZERO -> NEG)
        ------------------------------------------------------------------------
        do_reset;
        startup;
        state_i <= ST_NEG_IN;
        do_sync;
        wait_cycles(10);  -- Less than dead time
        check("T15.1 - Dead time: ZERO_N during transition", pwm_o = VEC_ZERO_N);
        wait_us(2);
        check("T15.2 - Dead time: NEG after transition", pwm_o = VEC_NEG);

        ------------------------------------------------------------------------
        -- TEST 16: Min pulse enforcement
        ------------------------------------------------------------------------
        do_reset;
        startup;
        state_i <= ST_POS_IN;
        do_sync;
        wait_us(2);
        state_i <= ST_ZERO_IN;
        do_sync;
        wait_cycles(10);  -- Less than min pulse
        check("T16.1 - Min pulse: still ZERO_P (waiting)", pwm_o = VEC_ZERO_P or pwm_o = VEC_POS);

        ------------------------------------------------------------------------
        -- TEST 17: Enable sync with sync_i
        ------------------------------------------------------------------------
        do_reset;
        state_i <= ST_POS_IN;
        en_i <= '1';
        wait_cycles(50);  -- No sync pulse
        check("T17.1 - Enable not synced yet", pwm_o = VEC_OFF);
        do_sync;
        state_i <= ST_ZERO_IN;
        do_sync;
        wait_us(2);
        check("T17.2 - Enable synced after sync pulse", pwm_o = VEC_ZERO);

        ------------------------------------------------------------------------
        -- Summary
        ------------------------------------------------------------------------
        wait_cycles(10);
        report "========================================";
        report "  PASS: " & integer'image(test_pass);
        report "  FAIL: " & integer'image(test_fail);
        report "========================================";

        if test_fail = 0 then
            report "ALL TESTS PASSED!" severity note;
        else
            report "SOME TESTS FAILED!" severity error;
        end if;

        test_done <= true;
        wait;
    end process;

end architecture;
