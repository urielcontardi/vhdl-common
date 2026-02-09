--! \file		tb_Fifo_Async.vhd
--!
--! \brief		
--!
--! \author		Uriel Abe Contardi (urielcontardi@hotmail.com)
--! \date       08-02-2026
--!
--! \version    1.0
--!
--! \copyright	Copyright (c) 2025 - All Rights reserved.
--!
--! \note		Target devices : No specific target
--! \note		Tool versions  : No specific tool
--! \note		Dependencies   : No specific dependencies
--!
--! \ingroup	None
--! \warning	None
--!
--! \note		Revisions:
--!				- 1.0	08-02-2026	<urielcontardi@hotmail.com>
--!				First revision.
--------------------------------------------------------------------------
-- Standard libraries
--------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_Fifo_Async is
end entity tb_Fifo_Async;

architecture Behavioral of tb_Fifo_Async is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant C_CLK_PERIOD   : time    := 10 ns;  -- 100 MHz
    constant C_DATA_WIDTH   : integer := 8;
    constant C_ADDR_BITS    : integer := 3;      -- Depth = 8 (smaller for async)

    ---------------------------------------------------------------------------
    -- DUT Signals
    ---------------------------------------------------------------------------
    signal clk           : std_logic := '0';
    signal rst_n         : std_logic := '0';
    signal wr_en         : std_logic := '0';
    signal wr_data       : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');
    signal rd_en         : std_logic := '0';
    signal rd_data       : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    signal is_empty      : std_logic;
    signal almost_empty  : std_logic;
    signal is_full       : std_logic;
    signal fill_level    : std_logic_vector(C_ADDR_BITS downto 0);

    ---------------------------------------------------------------------------
    -- Test Control
    ---------------------------------------------------------------------------
    signal sim_done      : boolean := false;
    signal test_passed   : integer := 0;
    signal test_failed   : integer := 0;

    ---------------------------------------------------------------------------
    -- Procedures
    ---------------------------------------------------------------------------
    procedure wait_cycles(signal clk : in std_logic; n : in positive) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

begin

    ---------------------------------------------------------------------------
    -- Clock Generation
    ---------------------------------------------------------------------------
    clk <= not clk after C_CLK_PERIOD / 2 when not sim_done else '0';

    ---------------------------------------------------------------------------
    -- DUT Instantiation (Combinatorial/Async Output Mode)
    ---------------------------------------------------------------------------
    DUT : entity work.Fifo
        generic map (
            G_DATA_WIDTH     => C_DATA_WIDTH,
            G_ADDR_BITS      => C_ADDR_BITS,
            G_REGISTERED_OUT => false  -- Async mode
        )
        port map (
            clk_i          => clk,
            rst_n_i        => rst_n,
            wr_en_i        => wr_en,
            wr_data_i      => wr_data,
            rd_en_i        => rd_en,
            rd_data_o      => rd_data,
            is_empty_o     => is_empty,
            almost_empty_o => almost_empty,
            is_full_o      => is_full,
            fill_level_o   => fill_level
        );

    ---------------------------------------------------------------------------
    -- Stimulus Process
    ---------------------------------------------------------------------------
    Stimulus_Proc : process
    begin
        report "=== FIFO Async Mode Testbench Started ===" severity note;

        -- Initial reset
        rst_n   <= '0';
        wr_en   <= '0';
        rd_en   <= '0';
        wr_data <= (others => '0');
        wait_cycles(clk, 5);
        rst_n <= '1';
        wait_cycles(clk, 2);

        ------------------------------------------------------------------------
        -- TEST 1: Zero-latency read test
        ------------------------------------------------------------------------
        report "TEST 1: Zero-latency read (async mode)" severity note;
        
        -- Write data
        wr_data <= x"55";
        wr_en   <= '1';
        wait_cycles(clk, 1);
        wr_en   <= '0';
        
        -- In async mode, data should be available immediately after write is registered
        wait_cycles(clk, 1);
        
        -- Check that empty flag updates immediately (no pipeline)
        if is_empty = '0' then
            report "  PASS: Empty flag updates without pipeline delay" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: Empty flag should be 0" severity error;
            test_failed <= test_failed + 1;
        end if;

        -- Data should be available at output (combinatorial read)
        if rd_data = x"55" then
            report "  PASS: Data available immediately at output" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: Expected 0x55 at output" severity error;
            test_failed <= test_failed + 1;
        end if;

        ------------------------------------------------------------------------
        -- TEST 2: Sequential write/read pattern
        ------------------------------------------------------------------------
        report "TEST 2: Sequential write/read" severity note;
        
        -- Read the existing element first
        rd_en <= '1';
        wait_cycles(clk, 1);
        rd_en <= '0';
        wait_cycles(clk, 1);

        -- Write 4 elements
        for i in 1 to 4 loop
            wr_data <= std_logic_vector(to_unsigned(i * 10, C_DATA_WIDTH));
            wr_en   <= '1';
            wait_cycles(clk, 1);
        end loop;
        wr_en <= '0';
        wait_cycles(clk, 1);

        -- Read and verify
        for i in 1 to 4 loop
            if rd_data = std_logic_vector(to_unsigned(i * 10, C_DATA_WIDTH)) then
                report "  Read " & integer'image(i) & ": OK" severity note;
            else
                report "  Read " & integer'image(i) & ": FAIL" severity error;
                test_failed <= test_failed + 1;
            end if;
            rd_en <= '1';
            wait_cycles(clk, 1);
            rd_en <= '0';
            wait_cycles(clk, 1);
        end loop;
        
        test_passed <= test_passed + 1;

        ------------------------------------------------------------------------
        -- Summary
        ------------------------------------------------------------------------
        wait_cycles(clk, 5);
        report "===================================================" severity note;
        report "=== ASYNC MODE TEST SUMMARY ===" severity note;
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

end architecture;
