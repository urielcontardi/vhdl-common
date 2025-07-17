--! \file		LinearSolver_Handler_tb.vhd
--!
--! \brief		
--!
--! \author		Vinícius Longo (longo.vinicius@gmail.com)
--! \date       17-07-2025
--!
--! \version    1.0
--!
--! \copyright	Copyright (c) 2025 - All Rights reserved.
--!
--! \note		Target devices : No specific target
--! \note		Tool versions  : No specific tool
--! \note		Dependencies   : No specific dependencies
--!
--! \ingroup
--! \warning	None
--!
--! \note		Revisions:
--!				
--------------------------------------------------------------------------
-- Default libraries
--------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.finish;
--------------------------------------------------------------------------
-- User packages
--------------------------------------------------------------------------
use work.Solver_pkg.all; 

--------------------------------------------------------------------------
-- Testbench Entity
--------------------------------------------------------------------------
entity LinearSolver_Handler_tb is
end entity LinearSolver_Handler_tb;

--------------------------------------------------------------------------
-- Testbench Architecture
--------------------------------------------------------------------------
architecture sim of LinearSolver_Handler_tb is

    --------------------------------------------------------------------------
    -- Constants definition
    --------------------------------------------------------------------------
    constant N_SS_TB        : natural := 5;
    constant N_IN_TB        : natural := 2;
    constant CLK_PERIOD     : time    := 10 ns; -- Clock de 100 MHz

    --------------------------------------------------------------------------
    -- Factors
    --------------------------------------------------------------------------
    constant AMATRIX : matrix_fp_t(0 to N_SS_TB - 1, 0 to N_SS_TB - 1) := (
        (x"000100000000", x"000100000000", x"000100000000", x"000100000000", x"000100000000"),
        (x"000200000000", x"000100000000", x"000100000000", x"000100000000", x"000100000000"),
        (x"000300000000", x"000100000000", x"000100000000", x"000100000000", x"000100000000"),
        (x"000400000000", x"000100000000", x"000100000000", x"000100000000", x"000100000000"),
        (x"000500000000", x"000100000000", x"000100000000", x"000100000000", x"000100000000")
    );
    
    constant BMATRIX : matrix_fp_t(0 to N_SS_TB - 1, 0 to N_IN_TB - 1) := (
        (x"000100000000", x"000100000000"),
        (x"000100000000", x"000100000000"),
        (x"000100000000", x"000100000000"),
        (x"000100000000", x"000100000000"),
        (x"000100000000", x"000100000000")
    );

    constant XVECTOR : vector_fp_t(0 to N_SS_TB - 1) := (
        x"000100000000", x"000200000000", x"000300000000", x"000400000000", x"000500000000"
    );

    constant UVECTOR : vector_fp_t(0 to N_IN_TB - 1) := (
        x"000100000000", x"000200000000"
    );
    
    --------------------------------------------------------------------------
    -- UUT ports
    --------------------------------------------------------------------------
    signal sysclk_tb            : std_logic := '0';
    signal start_i_tb           : std_logic;
    signal Amatrix_i_tb         : matrix_fp_t(0 to N_SS_TB - 1, 0 to N_SS_TB - 1) := AMATRIX;
    signal Xvec_i_tb            : vector_fp_t(0 to N_SS_TB - 1) := XVECTOR;
    signal Bmatrix_i_tb         : matrix_fp_t(0 to N_SS_TB - 1, 0 to N_IN_TB - 1) := BMATRIX;
    signal Uvec_i_tb            : vector_fp_t(0 to N_IN_TB - 1) := UVECTOR;
    signal stateResult_o_tb     : vector_fp_t(0 to N_SS_TB - 1);
    signal busy_o_tb            : std_logic;

begin

    --------------------------------------------------------------------------
    -- Unit Under Test
    --------------------------------------------------------------------------
    LSH: Entity work.LinearSolver_Handler
    generic map (
        N_SS            => N_SS_TB,
        N_IN            => N_IN_TB
    )
    Port map(
        sysclk          => sysclk_tb,       
        start_i         => start_i_tb,      
        Amatrix         => Amatrix_i_tb,    
        Xvec_i          => Xvec_i_tb,    
        Bmatrix         => Bmatrix_i_tb,    
        Uvec_i          => Uvec_i_tb,    
        stateVector_o   => stateResult_o_tb,
        busy_o          => busy_o_tb       
    );


    --------------------------------------------------------------------------
    -- Clk generation
    --------------------------------------------------------------------------
    clk_process: process
    begin
        sysclk_tb <= '0';
        wait for CLK_PERIOD / 2;
        sysclk_tb <= '1';
        wait for CLK_PERIOD / 2;
    end process;


    --------------------------------------------------------------------------
    -- Stimulus
    --------------------------------------------------------------------------
    stimulus_process: process

    begin
        start_i_tb <= '0';
        wait for 10 * CLK_PERIOD;
        start_i_tb <= '1'; 
        wait for CLK_PERIOD;
        start_i_tb <= '0';
        wait until busy_o_tb = '0';
        wait for 10 * CLK_PERIOD;
        start_i_tb <= '1';
        wait for CLK_PERIOD;
        start_i_tb <= '0';
        wait until busy_o_tb = '0';
        wait for 10 * CLK_PERIOD;
        finish;
    end process;


end architecture sim;