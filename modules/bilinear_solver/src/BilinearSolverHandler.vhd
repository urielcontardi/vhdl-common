--! \file		BilinearSolverHandler.vhd
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

--------------------------------------------------------------------------
-- User packages
--------------------------------------------------------------------------
use work.BilinearSolverPkg.all;

--------------------------------------------------------------------------
-- Entity declaration
--------------------------------------------------------------------------
Entity BilinearSolverHandler is
    Generic (
        N_SS    : natural := 5;    -- Number of State Space
        N_IN    : natural := 2     -- Inputs number of State Space
    );
    Port (
        sysclk              : in std_logic;
        start_i             : in std_logic;

        Amatrix_i           : in matrix_fp_t(0 to N_SS - 1, 0 to N_SS - 1);
        Xvec_i              : in vector_fp_t(0 to N_SS - 1);
        Ymatrix_i           : in matrix_fp_t(0 to N_SS - 1, 0 to N_SS - 1);
        Bmatrix_i           : in matrix_fp_t(0 to N_SS - 1, 0 to N_IN - 1);
        Uvec_i              : in vector_fp_t(0 to N_IN - 1);

        stateResultVec_o    : out vector_fp_t(0 to N_SS - 1);
        busy_o              : out std_logic 
    );
End entity;

--------------------------------------------------------------------------
-- Architecture
--------------------------------------------------------------------------
Architecture rtl of BilinearSolverHandler is

    signal busy_vec     : std_logic_vector(0 to N_SS -1);
    signal start_sig    : std_logic;  

Begin

    BilinearSolverUnit_Gen : for index in 0 to N_SS-1 generate
        signal A_row : vector_fp_t(0 to N_SS - 1);
        signal B_row : vector_fp_t(0 to N_IN - 1);
        signal Y_row : vector_fp_t(0 to N_SS - 1);
    begin 
        Row_Extract_Process: process(Amatrix_i, Bmatrix_i, Ymatrix_i)
        begin
            for j in 0 to N_SS-1 loop
                A_row(j) <= Amatrix_i(index, j);
                Y_row(j) <= Ymatrix_i(index, j);
            end loop;
            for j in 0 to N_IN-1 loop
                B_row(j) <= Bmatrix_i(index, j);
            end loop;
        end process;

        BSU: Entity work.BilinearSolverUnit
        Generic map (
            N_SS            => N_SS,
            N_IN            => N_IN
        )
        Port map (
            sysclk          => sysclk,
            start_i         => start_i,
            Avec_i          => A_row,
            Xvec_i          => Xvec_i,
            Yvec_i          => Y_row,
            Bvec_i          => B_row,
            Uvec_i          => Uvec_i,
            stateResult_o   => stateResultVec_o(index),
            busy_o          => busy_vec(index)
        );
    End generate;

    busy_o <= '1' when (busy_vec /= (busy_vec'range => '0')) else '0';

End architecture;
