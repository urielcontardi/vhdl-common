--! \file		LinearSolver_Unit_tb.vhd
--!
--! \brief		stateResult_o = A*X + B*U
--!
--! \author		Vinícius Longo (longo.vinicius@gmail.com)
--! \date       14-07-2025
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
entity LinearSolver_Unit_tb is
end entity LinearSolver_Unit_tb;

--------------------------------------------------------------------------
-- Testbench Architecture
--------------------------------------------------------------------------
architecture sim of LinearSolver_Unit_tb is

    --------------------------------------------------------------------------
    -- Constants definition
    --------------------------------------------------------------------------
    constant N_SS_TB        : natural := 5;
    constant N_IN_TB        : natural := 2;
    constant CLK_PERIOD     : time    := 10 ns; -- Clock de 100 MHz

    --------------------------------------------------------------------------
    -- Factors
    --------------------------------------------------------------------------
    constant FACTORS1       : vector_fp_t(0 to N_SS_TB - 1) := (
        x"000100000000", x"000100000000", x"000100000000", x"000100000000", x"000100000000"
    );

    constant FACTORS2       : vector_fp_t(0 to N_IN_TB - 1) := (
        x"000200000000", x"000200000000"
    );

    --------------------------------------------------------------------------
    -- UUT ports
    --------------------------------------------------------------------------
    signal sysclk_tb        : std_logic := '0';
    signal start_i_tb       : std_logic;
    signal Avec_i_tb        : vector_fp_t(0 to N_SS_TB - 1) := FACTORS1;
    signal Xvec_i_tb        : vector_fp_t(0 to N_SS_TB - 1) := FACTORS1;
    signal Bvec_i_tb        : vector_fp_t(0 to N_IN_TB - 1) := FACTORS2;
    signal Uvec_i_tb        : vector_fp_t(0 to N_IN_TB - 1) := FACTORS2;
    signal stateResult_o_tb : fixed_point_data_t;
    signal busy_o_tb        : std_logic;

begin

    --------------------------------------------------------------------------
    -- Unit Under Test
    --------------------------------------------------------------------------
    uut: Entity work.LinearSolver
        generic map (
            N_SS => N_SS_TB,
            N_IN => N_IN_TB
        )
        port map (
            sysclk        => sysclk_tb,
            start_i       => start_i_tb,
            Avec_i        => Avec_i_tb,
            Xvec_i        => Xvec_i_tb,
            Bvec_i        => Bvec_i_tb,
            Uvec_i        => Uvec_i_tb,
            stateResult_o => stateResult_o_tb,
            busy_o        => busy_o_tb
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