--! \file		tb_Fifo.vhd
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

entity tb_Fifo is
end entity tb_Fifo;

architecture Behavioral of tb_Fifo is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant C_CLK_PERIOD   : time    := 10 ns;  -- 100 MHz
    constant C_DATA_WIDTH   : integer := 8;
    constant C_ADDR_BITS    : integer := 4;      -- Depth = 16
    constant C_FIFO_DEPTH   : integer := 2 ** C_ADDR_BITS;

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
    -- DUT Instantiation (Registered Output Mode)
    ---------------------------------------------------------------------------
    DUT : entity work.Fifo
        generic map (
            G_DATA_WIDTH     => C_DATA_WIDTH,
            G_ADDR_BITS      => C_ADDR_BITS,
            G_REGISTERED_OUT => true
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
        variable v_expected : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    begin
        report "=== FIFO Testbench Started ===" severity note;

        -- Initial reset
        rst_n   <= '0';
        wr_en   <= '0';
        rd_en   <= '0';
        wr_data <= (others => '0');
        wait_cycles(clk, 5);
        rst_n <= '1';
        wait_cycles(clk, 2);

        ------------------------------------------------------------------------
        -- TEST 1: Check initial state (empty after reset)
        ------------------------------------------------------------------------
        report "TEST 1: Initial state check" severity note;
        if is_empty = '1' and is_full = '0' and almost_empty = '1' then
            report "  PASS: FIFO is empty after reset" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: FIFO should be empty after reset" severity error;
            test_failed <= test_failed + 1;
        end if;
        wait_cycles(clk, 2);

        ------------------------------------------------------------------------
        -- TEST 2: Write single element
        ------------------------------------------------------------------------
        report "TEST 2: Write single element" severity note;
        wr_data <= x"AA";
        wr_en   <= '1';
        wait_cycles(clk, 1);
        wr_en   <= '0';
        wait_cycles(clk, 3);  -- Wait for pipeline (write + status + read register)

        if is_empty = '0' then
            report "  PASS: FIFO not empty after write" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: FIFO should not be empty" severity error;
            test_failed <= test_failed + 1;
        end if;

        ------------------------------------------------------------------------
        -- TEST 3: Read single element
        -- In registered mode, data appears at output 1 cycle after rd_en
        -- The output register continuously shows the head of the FIFO
        ------------------------------------------------------------------------
        report "TEST 3: Read single element" severity note;
        
        -- Data should already be at output (registered from RAM)
        wait_cycles(clk, 1);
        
        -- Check data before reading
        if rd_data = x"AA" then
            report "  PASS: Read correct data (0xAA)" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: Expected 0xAA, got 0x" & 
                   integer'image(to_integer(unsigned(rd_data))) severity error;
            test_failed <= test_failed + 1;
        end if;

        -- Now actually consume the element
        rd_en <= '1';
        wait_cycles(clk, 1);
        rd_en <= '0';
        
        -- Check empty after read
        wait_cycles(clk, 2);
        if is_empty = '1' then
            report "  PASS: FIFO empty after reading last element" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: FIFO should be empty" severity error;
            test_failed <= test_failed + 1;
        end if;

        ------------------------------------------------------------------------
        -- TEST 4: Fill FIFO completely
        ------------------------------------------------------------------------
        report "TEST 4: Fill FIFO to full (" & integer'image(C_FIFO_DEPTH) & 
               " elements)" severity note;
        
        for i in 0 to C_FIFO_DEPTH - 1 loop
            wr_data <= std_logic_vector(to_unsigned(i, C_DATA_WIDTH));
            wr_en   <= '1';
            wait_cycles(clk, 1);
        end loop;
        wr_en <= '0';
        wait_cycles(clk, 2);

        if is_full = '1' then
            report "  PASS: FIFO is full" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: FIFO should be full" severity error;
            test_failed <= test_failed + 1;
        end if;

        ------------------------------------------------------------------------
        -- TEST 5: Overflow protection (write when full)
        ------------------------------------------------------------------------
        report "TEST 5: Overflow protection" severity note;
        wr_data <= x"FF";
        wr_en   <= '1';
        wait_cycles(clk, 1);
        wr_en   <= '0';
        wait_cycles(clk, 1);

        -- FIFO should still be full, data should not be written
        if is_full = '1' then
            report "  PASS: Overflow protected" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: Overflow not protected" severity error;
            test_failed <= test_failed + 1;
        end if;

        ------------------------------------------------------------------------
        -- TEST 6: Read all elements and verify FIFO order
        ------------------------------------------------------------------------
        report "TEST 6: Read all and verify FIFO order" severity note;
        
        for i in 0 to C_FIFO_DEPTH - 1 loop
            rd_en <= '1';
            wait_cycles(clk, 1);
            rd_en <= '0';
            wait_cycles(clk, 1);
            
            v_expected := std_logic_vector(to_unsigned(i, C_DATA_WIDTH));
            if rd_data = v_expected then
                null;  -- OK
            else
                report "  FAIL: At index " & integer'image(i) & 
                       " expected " & integer'image(i) & 
                       " got " & integer'image(to_integer(unsigned(rd_data))) 
                       severity error;
                test_failed <= test_failed + 1;
            end if;
        end loop;

        wait_cycles(clk, 2);
        if is_empty = '1' then
            report "  PASS: FIFO empty after reading all" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: FIFO should be empty" severity error;
            test_failed <= test_failed + 1;
        end if;

        ------------------------------------------------------------------------
        -- TEST 7: Underflow protection (read when empty)
        ------------------------------------------------------------------------
        report "TEST 7: Underflow protection" severity note;
        rd_en <= '1';
        wait_cycles(clk, 1);
        rd_en <= '0';
        wait_cycles(clk, 1);

        if is_empty = '1' then
            report "  PASS: Underflow protected" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: Underflow not protected" severity error;
            test_failed <= test_failed + 1;
        end if;

        ------------------------------------------------------------------------
        -- TEST 8: Simultaneous read/write
        ------------------------------------------------------------------------
        report "TEST 8: Simultaneous read/write" severity note;
        
        -- First, write some data
        for i in 0 to 3 loop
            wr_data <= std_logic_vector(to_unsigned(i + 100, C_DATA_WIDTH));
            wr_en   <= '1';
            wait_cycles(clk, 1);
        end loop;
        wr_en <= '0';
        wait_cycles(clk, 2);

        -- Now do simultaneous read/write
        wr_data <= x"DD";
        wr_en   <= '1';
        rd_en   <= '1';
        wait_cycles(clk, 1);
        wr_en   <= '0';
        rd_en   <= '0';
        wait_cycles(clk, 2);

        -- Fill level should remain the same (4 elements)
        if unsigned(fill_level) = 4 then
            report "  PASS: Fill level unchanged during simultaneous R/W" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: Fill level = " & integer'image(to_integer(unsigned(fill_level))) & 
                   " (expected 4)" severity error;
            test_failed <= test_failed + 1;
        end if;

        ------------------------------------------------------------------------
        -- TEST 9: almost_empty signal check
        ------------------------------------------------------------------------
        report "TEST 9: almost_empty signal check" severity note;
        
        -- Empty the FIFO first
        while is_empty = '0' loop
            rd_en <= '1';
            wait_cycles(clk, 1);
        end loop;
        rd_en <= '0';
        wait_cycles(clk, 2);

        -- Write one element
        wr_data <= x"11";
        wr_en   <= '1';
        wait_cycles(clk, 1);
        wr_en   <= '0';
        wait_cycles(clk, 2);

        if almost_empty = '1' then
            report "  PASS: almost_empty = 1 with 1 element" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: almost_empty should be 1" severity error;
            test_failed <= test_failed + 1;
        end if;

        -- Write second element
        wr_data <= x"22";
        wr_en   <= '1';
        wait_cycles(clk, 1);
        wr_en   <= '0';
        wait_cycles(clk, 2);

        if almost_empty = '0' then
            report "  PASS: almost_empty = 0 with 2 elements" severity note;
            test_passed <= test_passed + 1;
        else
            report "  FAIL: almost_empty should be 0" severity error;
            test_failed <= test_failed + 1;
        end if;

        ------------------------------------------------------------------------
        -- Summary
        ------------------------------------------------------------------------
        wait_cycles(clk, 5);
        report "===================================================" severity note;
        report "=== TEST SUMMARY ===" severity note;
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
