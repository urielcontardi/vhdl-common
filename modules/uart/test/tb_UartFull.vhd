--------------------------------------------------------------------------
--! @file       tb_UartFull.vhd
--! @brief      Testbench for UartFull module (Complete UART with FIFOs)
--!             Tests TX and RX paths with FIFO buffering in loopback.
--! @author     Uriel Abe Contardi (urielcontardi@hotmail.com)
--! @date       08-02-2026
--! @version    1.0
--------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_UartFull is
end entity tb_UartFull;

architecture Behavioral of tb_UartFull is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant C_CLK_FREQ     : integer := 100_000_000;  -- 100 MHz
    constant C_BAUD_RATE    : integer := 115200;
    constant C_CLK_PERIOD   : time    := 10 ns;
    constant C_BIT_PERIOD   : time    := (1 sec / C_BAUD_RATE);
    constant C_DATA_WIDTH   : integer := 8;
    constant C_TX_FIFO_DEPTH: integer := 4;  -- 16 entries
    constant C_RX_FIFO_DEPTH: integer := 4;  -- 16 entries

    ---------------------------------------------------------------------------
    -- DUT Signals
    ---------------------------------------------------------------------------
    signal clk              : std_logic := '0';
    signal rst_n            : std_logic := '0';
    
    -- TX Interface
    signal tx_data          : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');
    signal tx_wr_en         : std_logic := '0';
    signal tx_enable        : std_logic := '1';
    signal tx_full          : std_logic;
    signal tx_empty         : std_logic;
    signal tx_count         : std_logic_vector(C_TX_FIFO_DEPTH downto 0);
    
    -- RX Interface
    signal rx_data          : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    signal rx_rd_en         : std_logic := '0';
    signal rx_empty         : std_logic;
    signal rx_full          : std_logic;
    signal rx_count         : std_logic_vector(C_RX_FIFO_DEPTH downto 0);
    
    -- Status
    signal rx_error         : std_logic;
    signal rx_timeout       : std_logic;
    signal tx_busy          : std_logic;
    signal rx_busy          : std_logic;
    
    -- Physical
    signal tx_line          : std_logic;
    signal rx_line          : std_logic;

    ---------------------------------------------------------------------------
    -- Test Control
    ---------------------------------------------------------------------------
    signal sim_done         : boolean := false;
    signal test_passed      : integer := 0;
    signal test_failed      : integer := 0;

    ---------------------------------------------------------------------------
    -- Procedures
    ---------------------------------------------------------------------------
    procedure wait_cycles(signal clk_sig : in std_logic; n : in positive) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk_sig);
        end loop;
    end procedure;

    procedure write_tx_fifo(
        signal clk_sig : in std_logic;
        signal wr_en   : out std_logic;
        signal data    : out std_logic_vector(7 downto 0);
        constant byte  : in std_logic_vector(7 downto 0)
    ) is
    begin
        data  <= byte;
        wr_en <= '1';
        wait until rising_edge(clk_sig);
        wr_en <= '0';
    end procedure;

    procedure read_rx_fifo(
        signal clk_sig : in std_logic;
        signal rd_en   : out std_logic
    ) is
    begin
        rd_en <= '1';
        wait until rising_edge(clk_sig);
        rd_en <= '0';
        wait until rising_edge(clk_sig);  -- Wait for data
        wait until rising_edge(clk_sig);  -- Extra cycle for registered output
    end procedure;

begin

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
    clk <= not clk after C_CLK_PERIOD / 2 when not sim_done else '0';

    ---------------------------------------------------------------------------
    -- Loopback Connection
    ---------------------------------------------------------------------------
    rx_line <= tx_line;

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    DUT : entity work.UartFull
        generic map (
            G_CLK_FREQ      => C_CLK_FREQ,
            G_BAUD_RATE     => C_BAUD_RATE,
            G_DATA_WIDTH    => C_DATA_WIDTH,
            G_TX_FIFO_DEPTH => C_TX_FIFO_DEPTH,
            G_RX_FIFO_DEPTH => C_RX_FIFO_DEPTH,
            G_FIFO_REG_OUT  => true,
            G_RX_TIMEOUT    => 20
        )
        port map (
            clk_i        => clk,
            rst_n_i      => rst_n,
            -- TX
            tx_data_i    => tx_data,
            tx_wr_en_i   => tx_wr_en,
            tx_enable_i  => tx_enable,
            tx_full_o    => tx_full,
            tx_empty_o   => tx_empty,
            tx_count_o   => tx_count,
            -- RX
            rx_data_o    => rx_data,
            rx_rd_en_i   => rx_rd_en,
            rx_empty_o   => rx_empty,
            rx_full_o    => rx_full,
            rx_count_o   => rx_count,
            -- Status
            rx_error_o   => rx_error,
            rx_timeout_o => rx_timeout,
            tx_busy_o    => tx_busy,
            rx_busy_o    => rx_busy,
            -- Physical
            tx_o         => tx_line,
            rx_i         => rx_line
        );

    ---------------------------------------------------------------------------
    -- Stimulus Process
    ---------------------------------------------------------------------------
    Stimulus_Proc : process
        variable v_timeout : integer;
    begin
        report "=== UartFull Testbench Started ===" severity note;
        report "    Clock: " & integer'image(C_CLK_FREQ/1_000_000) & " MHz" severity note;
        report "    Baud:  " & integer'image(C_BAUD_RATE) & " bps" severity note;
        report "    TX FIFO: " & integer'image(2**C_TX_FIFO_DEPTH) & " entries" severity note;
        report "    RX FIFO: " & integer'image(2**C_RX_FIFO_DEPTH) & " entries" severity note;

        -- Initial reset
        rst_n     <= '0';
        tx_wr_en  <= '0';
        tx_enable <= '1';
        rx_rd_en  <= '0';
        wait_cycles(clk, 10);
        rst_n <= '1';
        wait_cycles(clk, 5);

        ------------------------------------------------------------------------
        -- TEST 1: Initial state check
        ------------------------------------------------------------------------
        report "TEST 1: Initial state check" severity note;
        
        if tx_empty = '1' and rx_empty = '1' and tx_full = '0' and rx_full = '0' then
            report "  PASS: FIFOs are empty after reset" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: FIFOs should be empty after reset" severity error;
            test_failed <= test_failed + 1;
        end if;

        if tx_line = '1' then
            report "  PASS: TX line is idle (high)" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: TX line should be high" severity error;
            test_failed <= test_failed + 1;
        end if;

        wait_cycles(clk, 10);

        ------------------------------------------------------------------------
        -- TEST 2: Single byte through FIFO
        ------------------------------------------------------------------------
        report "TEST 2: Single byte transmission via FIFO" severity note;
        
        -- Write to TX FIFO
        write_tx_fifo(clk, tx_wr_en, tx_data, x"42");
        
        wait_cycles(clk, 5);
        
        -- Check TX FIFO not empty
        if tx_empty = '0' then
            report "  PASS: TX FIFO has data" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: TX FIFO should have data" severity error;
            test_failed <= test_failed + 1;
        end if;

        -- Wait for transmission to complete and RX to receive
        v_timeout := 0;
        while rx_empty = '1' and v_timeout < 20000 loop
            wait until rising_edge(clk);
            v_timeout := v_timeout + 1;
        end loop;

        -- Wait a bit more for data to settle
        wait_cycles(clk, 100);

        if rx_empty = '0' then
            report "  PASS: RX FIFO received data" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: RX FIFO should have data (timeout)" severity error;
            test_failed <= test_failed + 1;
        end if;

        -- Read from RX FIFO
        read_rx_fifo(clk, rx_rd_en);

        if rx_data = x"42" then
            report "  PASS: Received correct data (0x42)" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: Expected 0x42, got 0x" & 
                   integer'image(to_integer(unsigned(rx_data))) severity error;
            test_failed <= test_failed + 1;
        end if;

        wait_cycles(clk, 100);

        ------------------------------------------------------------------------
        -- TEST 3: Burst write to TX FIFO (multiple bytes)
        ------------------------------------------------------------------------
        report "TEST 3: Burst write (5 bytes)" severity note;
        
        -- Write 5 bytes quickly to FIFO
        for i in 0 to 4 loop
            write_tx_fifo(clk, tx_wr_en, tx_data, 
                         std_logic_vector(to_unsigned(i + 16#30#, 8)));  -- '0', '1', '2', '3', '4'
        end loop;

        wait_cycles(clk, 5);
        
        report "  TX FIFO count: " & integer'image(to_integer(unsigned(tx_count))) severity note;
        
        if unsigned(tx_count) >= 1 then
            report "  PASS: TX FIFO has queued data" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: TX FIFO should have data" severity error;
            test_failed <= test_failed + 1;
        end if;

        -- Wait for all transmissions
        v_timeout := 0;
        while (tx_empty = '0' or tx_busy = '1') and v_timeout < 100000 loop
            wait until rising_edge(clk);
            v_timeout := v_timeout + 1;
        end loop;

        -- Wait for all RX data
        wait_cycles(clk, 1000);

        report "  RX FIFO count: " & integer'image(to_integer(unsigned(rx_count))) severity note;

        if unsigned(rx_count) = 5 then
            report "  PASS: RX FIFO received all 5 bytes" severity note;
            test_passed <= test_passed + 1;
        else
            report "  WARN: Expected 5 bytes in RX FIFO" severity warning;
        end if;

        -- Read and verify all bytes
        for i in 0 to 4 loop
            read_rx_fifo(clk, rx_rd_en);
            if rx_data = std_logic_vector(to_unsigned(i + 16#30#, 8)) then
                report "  Byte " & integer'image(i) & ": OK" severity note;
            else
                report "  Byte " & integer'image(i) & ": FAIL" severity error;
                test_failed <= test_failed + 1;
            end if;
        end loop;
        test_passed <= test_passed + 1;

        wait_cycles(clk, 100);

        ------------------------------------------------------------------------
        -- TEST 4: TX Enable control (flow control)
        ------------------------------------------------------------------------
        report "TEST 4: TX Enable flow control" severity note;
        
        -- Disable TX
        tx_enable <= '0';
        
        -- Write data to FIFO
        write_tx_fifo(clk, tx_wr_en, tx_data, x"FF");
        
        wait_cycles(clk, 100);
        
        -- Data should still be in TX FIFO (not transmitted)
        if tx_empty = '0' and tx_line = '1' then
            report "  PASS: TX held when disabled" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: TX should be held" severity error;
            test_failed <= test_failed + 1;
        end if;
        
        -- Re-enable TX
        tx_enable <= '1';
        
        -- Wait for transmission
        v_timeout := 0;
        while tx_empty = '0' and v_timeout < 20000 loop
            wait until rising_edge(clk);
            v_timeout := v_timeout + 1;
        end loop;
        
        if tx_empty = '1' then
            report "  PASS: TX resumed when enabled" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: TX should have transmitted" severity error;
            test_failed <= test_failed + 1;
        end if;

        -- Clear RX FIFO
        wait_cycles(clk, 1000);
        while rx_empty = '0' loop
            read_rx_fifo(clk, rx_rd_en);
        end loop;

        wait_cycles(clk, 100);

        ------------------------------------------------------------------------
        -- TEST 5: Error checking
        ------------------------------------------------------------------------
        report "TEST 5: No errors during operation" severity note;
        
        if rx_error = '0' then
            report "  PASS: No frame errors" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: Frame error detected" severity error;
            test_failed <= test_failed + 1;
        end if;

        ------------------------------------------------------------------------
        -- Summary
        ------------------------------------------------------------------------
        wait_cycles(clk, 100);
        report "===================================================" severity note;
        report "=== UART FULL TEST SUMMARY ===" severity note;
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

end architecture Behavioral;
