--! \file		tb_ClarkeTransform.vhd
--!
--! \brief		
--!
--! \author		Vinícius de Carvalho Monteiro Longo (longo.vinicius@gmail.com)
--! \date       23-07-2025
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
--!				- 1.0	23-07-2025	<longo.vinicius@gmail.com>
--!				First revision.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.finish;

entity tb_ClarkeTransform is
end entity tb_ClarkeTransform;

architecture sim of tb_ClarkeTransform is

    -- Testbench constants
    constant CLK_PERIOD     : time    := 10 ns;
    constant DATA_WIDTH_TB  : integer := 32;
    constant FRAC_WIDTH_TB  : integer := 16;
    
    -- Testbench signals
    signal clk_tb           : std_logic := '0';
    signal reset_n_tb       : std_logic;
    signal data_valid_i_tb  : std_logic;
    
    -- ABC inputs (signed)
    signal a_in_tb          : signed(DATA_WIDTH_TB-1 downto 0);
    signal b_in_tb          : signed(DATA_WIDTH_TB-1 downto 0);
    signal c_in_tb          : signed(DATA_WIDTH_TB-1 downto 0);
    
    -- Alpha-Beta-Zero outputs (signed)
    signal alpha_o_tb       : signed(DATA_WIDTH_TB-1 downto 0);
    signal beta_o_tb        : signed(DATA_WIDTH_TB-1 downto 0);
    signal zero_o_tb        : signed(DATA_WIDTH_TB-1 downto 0);
    signal data_valid_o_tb  : std_logic;
    
    -- Signals for visualization (real)
    signal a_real_tb        : real;
    signal b_real_tb        : real;
    signal c_real_tb        : real;
    signal alpha_real_tb    : real;
    signal beta_real_tb     : real;
    signal zero_real_tb     : real;

begin

    --------------------------------------------------------------------------
    -- UUT (Unit Under Test) instantiation
    --------------------------------------------------------------------------
    UUT_ClarkeTransform : entity work.ClarkeTransform
        generic map (
            DATA_WIDTH => DATA_WIDTH_TB,
            FRAC_WIDTH => FRAC_WIDTH_TB
        )
        port map (
            sysclk       => clk_tb,
            reset_n      => reset_n_tb,
            data_valid_i => data_valid_i_tb,
            a_in         => a_in_tb,
            b_in         => b_in_tb,
            c_in         => c_in_tb,
            alpha_o      => alpha_o_tb,
            beta_o       => beta_o_tb,
            zero_o       => zero_o_tb,
            data_valid_o => data_valid_o_tb
        );

    --------------------------------------------------------------------------
    -- Clock generation
    --------------------------------------------------------------------------
    clk_tb <= not clk_tb after CLK_PERIOD / 2;

    -- --------------------------------------------------------------------------
    -- -- Reset and stimulus process
    -- --------------------------------------------------------------------------
    stimulus_process: process

        procedure apply_abc_values(
            constant a_val : in real;
            constant b_val : in real;
            constant c_val : in real
        ) is
        begin
            a_in_tb <= to_signed(integer(a_val * (2.0**FRAC_WIDTH_TB)), DATA_WIDTH_TB);
            b_in_tb <= to_signed(integer(b_val * (2.0**FRAC_WIDTH_TB)), DATA_WIDTH_TB);
            c_in_tb <= to_signed(integer(c_val * (2.0**FRAC_WIDTH_TB)), DATA_WIDTH_TB);
            data_valid_i_tb <= '1';
            wait for CLK_PERIOD * 1;
            data_valid_i_tb <= '0';
        end procedure;

    begin

        wait until rising_edge(clk_tb);
        reset_n_tb <= '0';
        data_valid_i_tb <= '0';
        a_in_tb <= (others => '0');
        b_in_tb <= (others => '0');
        c_in_tb <= (others => '0');
        wait for CLK_PERIOD * 20;
        
        reset_n_tb <= '1';
        wait for CLK_PERIOD * 2;

        --------------------------------------------------------------------------
        -- TEST 1: Simple balanced system
        -- A=100, B=-50, C=-50 (sum = 0)
        -- Expected result: Alpha ≈ 100, Beta ≈ 0, Zero ≈ 0
        --------------------------------------------------------------------------
        apply_abc_values(100.0, -50.0, -50.0);
        
        wait for CLK_PERIOD * 5;

        --------------------------------------------------------------------------
        -- TEST 2: Unbalanced system
        -- A=100, B=0, C=0 (sum ≠ 0)
        -- Expected result: Alpha ≈ 66.7, Beta ≈ 0, Zero ≈ 33.3
        --------------------------------------------------------------------------
        apply_abc_values(100.0, 0.0, 0.0);

        wait for CLK_PERIOD * 5;

        --------------------------------------------------------------------------
        -- TEST 3: Equal values (common mode)
        -- A=50, B=50, C=50 (sum = 150)
        -- Expected result: Alpha ≈ 0, Beta ≈ 0, Zero ≈ 50
        --------------------------------------------------------------------------   
        apply_abc_values(50.0, 50.0, 50.0);     
        
        wait for CLK_PERIOD * 5;

        --------------------------------------------------------------------------
        -- TEST 4: Zeros
        -- A=0, B=0, C=0
        -- Expected result: Alpha=0, Beta=0, Zero=0
        --------------------------------------------------------------------------      
        apply_abc_values(0.0, 0.0, 0.0);       
        
        wait for CLK_PERIOD * 5;

        --------------------------------------------------------------------------
        -- End simulation
        --------------------------------------------------------------------------
        data_valid_i_tb <= '0';
        wait for CLK_PERIOD * 10;
                finish;
    end process;

    --------------------------------------------------------------------------
    -- Input conversion to real (for visualization)
    --------------------------------------------------------------------------
    input_conversion: process(a_in_tb, b_in_tb, c_in_tb)
    begin
        a_real_tb <= real(to_integer(a_in_tb)) / (2.0**FRAC_WIDTH_TB);
        b_real_tb <= real(to_integer(b_in_tb)) / (2.0**FRAC_WIDTH_TB);
        c_real_tb <= real(to_integer(c_in_tb)) / (2.0**FRAC_WIDTH_TB);
    end process;

    --------------------------------------------------------------------------
    -- Output conversion to real (for visualization)
    --------------------------------------------------------------------------
    output_conversion: process(alpha_o_tb, beta_o_tb, zero_o_tb)
    begin
        alpha_real_tb <= real(to_integer(alpha_o_tb)) / (2.0**FRAC_WIDTH_TB);
        beta_real_tb  <= real(to_integer(beta_o_tb))  / (2.0**FRAC_WIDTH_TB);
        zero_real_tb  <= real(to_integer(zero_o_tb))  / (2.0**FRAC_WIDTH_TB);
    end process;

end architecture sim;