--! \file		tb_BilinearSolverHandler.vhd
--!
--! \brief		
--!
--! \author		Uriel Abe Contardi (urielcontardi@hotmail.com)
--! \date       05-08-2025
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
--!				- 1.0	05-08-2025	<urielcontardi@hotmail.com>
--!				First revision.
--------------------------------------------------------------------------
-- Default libraries
--------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;
use std.env.finish;

--------------------------------------------------------------------------
-- User packages
--------------------------------------------------------------------------
use work.BilinearSolverPkg.all;

--------------------------------------------------------------------------
-- Entity declaration
--------------------------------------------------------------------------
Entity tb_BilinearSolverHandler is
End entity;

Architecture behavior of tb_BilinearSolverHandler is

    --------------------------------------------------------------------------
    -- Clock definition
    --------------------------------------------------------------------------
    constant CLK_FREQUENCY  : integer   := 200e6;
    constant CLK_PERIOD     : time      := 1 sec / CLK_FREQUENCY;

    --------------------------------------------------------------------------
    -- Testbench definition
    --------------------------------------------------------------------------
    constant N_SS        : natural := 5;
    constant N_IN        : natural := 2;

    constant AMATRIX : matrix_fp_t(0 to N_SS - 1, 0 to N_SS - 1) := (
        (to_fp(1.0), to_fp(1.0), to_fp(1.0), to_fp(1.0), to_fp(1.0)),
        (to_fp(2.0), to_fp(1.0), to_fp(1.0), to_fp(1.0), to_fp(1.0)),
        (to_fp(3.0), to_fp(1.0), to_fp(1.0), to_fp(1.0), to_fp(1.0)),
        (to_fp(4.0), to_fp(1.0), to_fp(1.0), to_fp(1.0), to_fp(1.0)),
        (to_fp(5.0), to_fp(1.0), to_fp(1.0), to_fp(1.0), to_fp(1.0))
    );
    
    constant BMATRIX : matrix_fp_t(0 to N_SS - 1, 0 to N_IN - 1) := (
        (to_fp(1.0), to_fp(1.0)),
        (to_fp(1.0), to_fp(1.0)),
        (to_fp(1.0), to_fp(1.0)),
        (to_fp(1.0), to_fp(1.0)),
        (to_fp(1.0), to_fp(1.0))
    );

    constant YMATRIX : matrix_fp_t(0 to N_SS - 1, 0 to N_SS - 1) := (
        (to_fp(-1.0), to_fp(-1.0), to_fp(-1.0), to_fp(-1.0), to_fp(-1.0)),
        (to_fp(-1.0), to_fp(-1.0), to_fp(-1.0), to_fp(-1.0), to_fp(-1.0)),
        (to_fp(-1.0), to_fp(-1.0), to_fp(-1.0), to_fp(-1.0), to_fp(-1.0)),
        (to_fp(-1.0), to_fp(-1.0), to_fp(-1.0), to_fp(-1.0), to_fp(-1.0)),
        (to_fp(-1.0), to_fp(-1.0), to_fp(-1.0), to_fp(-1.0), to_fp(-1.0))
    );

    constant XVECTOR : vector_fp_t(0 to N_SS - 1) := (
        to_fp(1.0), to_fp(2.0), to_fp(3.0), to_fp(4.0), to_fp(5.0)
    );

    constant UVECTOR : vector_fp_t(0 to N_IN - 1) := (
        to_fp(1.0), to_fp(1.0)
    );

    --------------------------------------------------------------------------
    -- UUT ports
    --------------------------------------------------------------------------
    -- Inputs
    signal sysclk              : std_logic := '0';
    signal start_i             : std_logic := '0';
    signal Amatrix_i           : matrix_fp_t(0 to N_SS - 1, 0 to N_SS - 1) := AMATRIX;
    signal Xvec_i              : vector_fp_t(0 to N_SS - 1) := XVECTOR;
    signal Ymatrix_i           : matrix_fp_t(0 to N_SS - 1, 0 to N_SS - 1) := YMATRIX;
    signal Bmatrix_i           : matrix_fp_t(0 to N_SS - 1, 0 to N_IN - 1) := BMATRIX;
    signal Uvec_i              : vector_fp_t(0 to N_IN - 1) := UVECTOR;
    signal stateResultVec_o    : vector_fp_t(0 to N_SS - 1);
    signal busy_o              : std_logic;

Begin

    --------------------------------------------------------------------------
    -- Clk generation
    --------------------------------------------------------------------------
    sysclk <= not sysclk after CLK_PERIOD/2;

    --------------------------------------------------------------------------
    -- UUT
    --------------------------------------------------------------------------
    uut: entity work.BilinearSolverHandler
    generic map (
        N_SS                => N_SS,
        N_IN                => N_IN
    )
    Port map(
        sysclk              => sysclk,
        start_i             => start_i,
        Amatrix_i           => Amatrix_i,
        Xvec_i              => Xvec_i,
        Ymatrix_i           => Ymatrix_i,
        Bmatrix_i           => Bmatrix_i,
        Uvec_i              => Uvec_i,
        stateResultVec_o    => stateResultVec_o,
        busy_o              => busy_o
    );

    --------------------------------------------------------------------------
    -- Stimulus
    --------------------------------------------------------------------------
    stimulus_process: process
    begin
        wait until rising_edge(sysclk);
        start_i <= '1';
        wait for CLK_PERIOD;
        start_i <= '0'; 
        wait for CLK_PERIOD * 50;
        finish;
    end process;

End architecture;
