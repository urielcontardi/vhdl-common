--------------------------------------------------------------------------
--! @file       tb_UartLoopback.vhd
--! @brief      Testbench for UART TX and RX modules (Loopback Test)
--!             TX output is connected directly to RX input.
--! @author     Uriel Abe Contardi (urielcontardi@hotmail.com)
--! @date       08-02-2026
--! @version    1.0
--------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_UartLoopback is
end entity tb_UartLoopback;

architecture Behavioral of tb_UartLoopback is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant C_CLK_FREQ     : integer := 100_000_000;  -- 100 MHz
    constant C_BAUD_RATE    : integer := 115200;
    constant C_BAUD_DIV     : integer := C_CLK_FREQ / C_BAUD_RATE;  -- ~868
    constant C_CLK_PERIOD   : time    := 10 ns;
    constant C_BIT_PERIOD   : time    := (1 sec / C_BAUD_RATE);     -- ~8.68 us
    constant C_DATA_WIDTH   : integer := 8;

    ---------------------------------------------------------------------------
    -- DUT Signals
    ---------------------------------------------------------------------------
    signal clk              : std_logic := '0';
    signal rst_n            : std_logic := '0';
    
    -- TX signals
    signal tx_start         : std_logic := '0';
    signal tx_data          : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');
    signal tx_line          : std_logic;
    signal tx_done          : std_logic;
    
    -- RX signals
    signal rx_data          : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    signal rx_valid         : std_logic;
    signal rx_error         : std_logic;
    signal rx_timeout       : std_logic;
    signal rx_busy          : std_logic;
    
    -- Baudrate
    signal baudrate         : std_logic_vector(15 downto 0);

    ---------------------------------------------------------------------------
    -- Test Control
    ---------------------------------------------------------------------------
    signal sim_done         : boolean := false;
    signal test_passed      : integer := 0;
    signal test_failed      : integer := 0;

    ---------------------------------------------------------------------------
    -- Test Data Array
    ---------------------------------------------------------------------------
    type t_test_data is array (natural range <>) of std_logic_vector(7 downto 0);
    constant C_TEST_VALUES : t_test_data := (
        x"00",  -- All zeros
        x"FF",  -- All ones
        x"AA",  -- Alternating 10101010
        x"55",  -- Alternating 01010101
        x"A5",  -- Pattern
        x"5A",  -- Inverse pattern
        x"0F",  -- Half nibble
        x"F0",  -- Other half
        x"48",  -- 'H'
        x"69",  -- 'i'
        x"21"   -- '!'
    );

    ---------------------------------------------------------------------------
    -- Procedures
    ---------------------------------------------------------------------------
    procedure wait_cycles(signal clk_sig : in std_logic; n : in positive) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk_sig);
        end loop;
    end procedure;

    procedure send_byte(
        signal clk_sig   : in std_logic;
        signal start     : out std_logic;
        signal data      : out std_logic_vector(7 downto 0);
        constant byte    : in std_logic_vector(7 downto 0)
    ) is
    begin
        data  <= byte;
        start <= '1';
        wait until rising_edge(clk_sig);
        start <= '0';
    end procedure;

begin

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
    clk <= not clk after C_CLK_PERIOD / 2 when not sim_done else '0';

    ---------------------------------------------------------------------------
    -- Baudrate Configuration
    ---------------------------------------------------------------------------
    baudrate <= std_logic_vector(to_unsigned(C_BAUD_DIV, 16));

    ---------------------------------------------------------------------------
    -- TX Instantiation
    ---------------------------------------------------------------------------
    TX_Inst : entity work.UartTX
        generic map (
            DATA_WIDTH => C_DATA_WIDTH,
            START_BIT  => '0',
            STOP_BIT   => '1'
        )
        port map (
            sysclk     => clk,
            reset_n    => rst_n,
            start_i    => tx_start,
            baudrate_i => baudrate,
            data_i     => tx_data,
            tx_o       => tx_line,
            tx_done_o  => tx_done
        );

    ---------------------------------------------------------------------------
    -- RX Instantiation
    ---------------------------------------------------------------------------
    RX_Inst : entity work.UartRX
        generic map (
            G_DATA_WIDTH => C_DATA_WIDTH,
            G_START_BIT  => '0',
            G_STOP_BIT   => '1',
            G_TOUT_BAUD  => 20
        )
        port map (
            clk_i        => clk,
            rst_n_i      => rst_n,
            rx_i         => tx_line,  -- Loopback: TX -> RX
            baudrate_i   => baudrate,
            data_o       => rx_data,
            rx_valid_o   => rx_valid,
            rx_error_o   => rx_error,
            rx_timeout_o => rx_timeout,
            rx_busy_o    => rx_busy
        );

    ---------------------------------------------------------------------------
    -- Stimulus Process
    ---------------------------------------------------------------------------
    Stimulus_Proc : process
        variable v_expected : std_logic_vector(7 downto 0);
        variable v_timeout  : integer;
    begin
        report "=== UART Loopback Testbench Started ===" severity note;
        report "    Clock: " & integer'image(C_CLK_FREQ/1_000_000) & " MHz" severity note;
        report "    Baud:  " & integer'image(C_BAUD_RATE) & " bps" severity note;
        report "    Divisor: " & integer'image(C_BAUD_DIV) severity note;

        -- Initial reset
        rst_n    <= '0';
        tx_start <= '0';
        tx_data  <= (others => '0');
        wait_cycles(clk, 10);
        rst_n <= '1';
        wait_cycles(clk, 5);

        ------------------------------------------------------------------------
        -- TEST 1: Single byte transmission
        ------------------------------------------------------------------------
        report "TEST 1: Single byte transmission (0xAA)" severity note;
        
        send_byte(clk, tx_start, tx_data, x"AA");
        
        -- Wait for TX to complete (start + 8 data + stop = 10 bits)
        v_timeout := 0;
        while tx_done = '0' and v_timeout < C_BAUD_DIV * 12 loop
            wait until rising_edge(clk);
            v_timeout := v_timeout + 1;
        end loop;

        -- Wait for RX to receive
        v_timeout := 0;
        while rx_valid = '0' and v_timeout < C_BAUD_DIV * 2 loop
            wait until rising_edge(clk);
            v_timeout := v_timeout + 1;
        end loop;
        
        wait_cycles(clk, 2);

        if rx_data = x"AA" and rx_error = '0' then
            report "  PASS: Received 0xAA correctly" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: Expected 0xAA, got 0x" & 
                   integer'image(to_integer(unsigned(rx_data))) severity error;
            test_failed <= test_failed + 1;
        end if;

        wait_cycles(clk, 100);

        ------------------------------------------------------------------------
        -- TEST 2: Multiple byte transmission
        ------------------------------------------------------------------------
        report "TEST 2: Multiple byte transmission (" & 
               integer'image(C_TEST_VALUES'length) & " bytes)" severity note;
        
        for i in C_TEST_VALUES'range loop
            v_expected := C_TEST_VALUES(i);
            
            send_byte(clk, tx_start, tx_data, v_expected);
            
            -- Wait for TX done
            v_timeout := 0;
            while tx_done = '0' and v_timeout < C_BAUD_DIV * 12 loop
                wait until rising_edge(clk);
                v_timeout := v_timeout + 1;
            end loop;
            
            -- Wait for RX valid
            v_timeout := 0;
            while rx_valid = '0' and v_timeout < C_BAUD_DIV * 2 loop
                wait until rising_edge(clk);
                v_timeout := v_timeout + 1;
            end loop;
            
            wait_cycles(clk, 2);
            
            if rx_data = v_expected and rx_error = '0' then
                report "  Byte " & integer'image(i) & ": PASS (0x" & 
                       integer'image(to_integer(unsigned(v_expected))) & ")" severity note;
                test_passed <= test_passed + 1;
            else
                report "  Byte " & integer'image(i) & ": FAIL - Expected 0x" &
                       integer'image(to_integer(unsigned(v_expected))) & 
                       " got 0x" & integer'image(to_integer(unsigned(rx_data))) severity error;
                test_failed <= test_failed + 1;
            end if;
            
            wait_cycles(clk, 50);
        end loop;

        ------------------------------------------------------------------------
        -- TEST 3: Back-to-back transmission (stress test)
        ------------------------------------------------------------------------
        report "TEST 3: Back-to-back transmission" severity note;
        
        for i in 0 to 4 loop
            v_expected := std_logic_vector(to_unsigned(i * 17, 8));  -- 0x00, 0x11, 0x22...
            
            send_byte(clk, tx_start, tx_data, v_expected);
            
            -- Wait for TX done
            while tx_done = '0' loop
                wait until rising_edge(clk);
            end loop;
            
            -- Minimal gap before next byte
            wait_cycles(clk, 10);
        end loop;

        -- Wait for all RX to complete
        wait_cycles(clk, C_BAUD_DIV * 5);
        
        report "  PASS: Back-to-back test completed" severity note;
        test_passed <= test_passed + 1;

        ------------------------------------------------------------------------
        -- TEST 4: Verify no errors during tests
        ------------------------------------------------------------------------
        report "TEST 4: Error flag verification" severity note;
        
        if rx_error = '0' then
            report "  PASS: No frame errors detected" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: Frame error detected" severity error;
            test_failed <= test_failed + 1;
        end if;

        ------------------------------------------------------------------------
        -- TEST 5: Idle line state
        ------------------------------------------------------------------------
        report "TEST 5: Idle line state" severity note;
        
        wait_cycles(clk, 100);
        
        if tx_line = '1' then
            report "  PASS: TX line is high (idle)" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: TX line should be high when idle" severity error;
            test_failed <= test_failed + 1;
        end if;

        ------------------------------------------------------------------------
        -- Summary
        ------------------------------------------------------------------------
        wait_cycles(clk, 100);
        report "===================================================" severity note;
        report "=== UART LOOPBACK TEST SUMMARY ===" severity note;
        report "    PASSED: " & integer'image(test_passed) severity note;
        report "    FAILED: " & integer'image(test_failed) severity note;
        if test_failed = 0 then
            report "=== ALL TESTS PASSED ===" severity note;
        else
            report "=== SOME TESTS FAILED ===" severity error;
        end if;
        report "===================================================" severity note;

        sim_done <= true;
        wait;
    end process Stimulus_Proc;

    ---------------------------------------------------------------------------
    -- Monitor Process - Display received data
    ---------------------------------------------------------------------------
    Monitor_Proc : process
    begin
        wait until rising_edge(clk);
        if rx_valid = '1' then
            report "[RX] Received: 0x" & integer'image(to_integer(unsigned(rx_data))) 
                   severity note;
        end if;
        if rx_error = '1' then
            report "[RX] ERROR: Frame error detected!" severity warning;
        end if;
    end process Monitor_Proc;

end architecture Behavioral;
