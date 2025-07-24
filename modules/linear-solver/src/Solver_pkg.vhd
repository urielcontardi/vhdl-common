--! \file		Solver_pkg.vhd
--!
--! \brief		
--!
--! \author		Uriel Abe Contardi (urielcontardi@hotmail.com)
--! \date       23-06-2024
--!
--! \version    1.1
--!
--! \copyright	Copyright (c) 2024 - All Rights reserved.
--!
--! \note		Target devices : No specific target
--! \note		Tool versions  : No specific tool
--! \note		Dependencies   : No specific dependencies
--!
--! \ingroup
--! \warning	None
--!
--! \note		Revisions:
--!				- 1.0	23-06-2024	<urielcontardi@hotmail.com>
--!             - 1.1   23-07-2025  <longo.vinicius@gmail.com>
--------------------------------------------------------------------------
-- Default libraries
--------------------------------------------------------------------------
Library ieee;
Use ieee.std_logic_1164.all;
Use ieee.numeric_std.all;
use ieee.math_real.all;

--------------------------------------------------------------------------
-- User packages
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- Package
--------------------------------------------------------------------------
Package Solver_pkg is
    
    --------------------------------------------------------------------------
    -- Constants
    --------------------------------------------------------------------------
    constant FP_INTEGER_BITS         : natural := 14;     
    constant FP_FRACTION_BITS         : natural := 28;     
    constant FP_TOTAL_BITS  : integer := FP_INTEGER_BITS + FP_FRACTION_BITS;

    subtype fixed_point_data_t is std_logic_vector(FP_TOTAL_BITS - 1 downto 0);
    type vector_fp_t is array (natural range <>) of fixed_point_data_t;
    type matrix_fp_t is array(natural range <>, natural range <>) of fixed_point_data_t;

    --------------------------------------------------------------------------
    -- Functions | Procedures
    --------------------------------------------------------------------------
    function getMatrixRow(matrix : matrix_fp_t; row : integer) return vector_fp_t;
    function to_fp (val : real) return fixed_point_data_t; 

End package;

Package body Solver_pkg is

    --------------------------------------------------------------------------
    -- getMatrixRow
    --------------------------------------------------------------------------
    function getMatrixRow(matrix : matrix_fp_t; row : integer) return vector_fp_t is
        variable result : vector_fp_t(matrix'range(2));
    begin
        for i in matrix'range(2) loop
            result(i) := matrix(row, i);
        end loop;
        return result;
    end function;

    --------------------------------------------------------------------------
    -- to_fp
    --------------------------------------------------------------------------
    function to_fp (val : real) return fixed_point_data_t is
        constant SCALE      : real      := 2.0 ** FP_FRACTION_BITS;
        variable int_val    : integer;
        variable signed_val : signed(FP_TOTAL_BITS - 1 downto 0);
    begin
        int_val := integer(val * SCALE);
        signed_val := to_signed(int_val, FP_TOTAL_BITS);

        return std_logic_vector(signed_val);
        
    end function to_fp;

End package body;