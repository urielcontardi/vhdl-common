--! \file		BilinearSolverPkg.vhd
--!
--! \brief		Packages for the Bilinear Solver
--!
--! \author		Uriel Abe Contardi (urielcontardi@hotmail.com)
--! \date       31-07-2025
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
--!				- 1.0	31-07-2025	<urielcontardi@hotmail.com>
--!				First revision.
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
Package BilinearSolverPkg is
    
    --------------------------------------------------------------------------
    -- Constants
    --------------------------------------------------------------------------
    constant FP_INTEGER_BITS          : natural := 14;
    constant FP_FRACTION_BITS         : natural := 28;
    constant FP_TOTAL_BITS            : integer := FP_INTEGER_BITS + FP_FRACTION_BITS;

    -- Coefficient format (A/B matrices) -- deliberately NOT the state format.
    -- Every A/B entry carries the factor Ts (130 ns), which crushes them to
    -- ~1e-7..1e-5; with only 28 fractional bits the smallest entry of a real
    -- motor matrix (Ts*lm*rr/Lr) survives on 9 LSBs, a 3.8% parameter error.
    -- States need the 14 integer bits (current/voltage/speed up to +-8192);
    -- coefficients never approach 1, so their integer bits are dead weight.
    -- Q4.38 keeps +-8 of range (>5000x margin over the largest entry seen from
    -- 0.1 kW to 1 MW) while giving the rotor-time-constant term Ts/tau_r more
    -- than 17000 levels for machines up to tau_r = 2 s.
    constant COEFF_FRACTION_BITS      : natural := 38;
    constant COEFF_INTEGER_BITS       : natural := FP_TOTAL_BITS - COEFF_FRACTION_BITS;

    subtype fixed_point_data_t is std_logic_vector(FP_TOTAL_BITS - 1 downto 0);
    type vector_fp_t is array (natural range <>) of fixed_point_data_t;
    type matrix_fp_t is array(natural range <>, natural range <>) of fixed_point_data_t;
    
    --------------------------------------------------------------------------
    -- Functions | Procedures
    --------------------------------------------------------------------------
    function to_fp (val : real) return fixed_point_data_t;
    -- Same conversion, but scaled by 2**COEFF_FRACTION_BITS. Use for A/B
    -- matrix entries; use to_fp for states, inputs and telemetry.
    function to_fp_coeff (val : real) return fixed_point_data_t;

End package;

Package body BilinearSolverPkg is

    --------------------------------------------------------------------------
    -- to_fp
    --------------------------------------------------------------------------
    function to_fp_frac (val : real; frac_bits : natural) return fixed_point_data_t is
        constant SCALE          : real      := 2.0 ** frac_bits;
        variable int_val        : real;
        variable result         : std_logic_vector(FP_TOTAL_BITS - 1 downto 0);
        variable is_negative    : boolean;
        variable abs_val        : real;
        variable temp_val       : real;
        variable bit_weight     : real;
    begin
        int_val := val * SCALE;
        
        -- Check if the value is negative
        is_negative := int_val < 0.0;
        abs_val := abs(int_val);
        
        -- Initialize result
        result := (others => '0');
        
        -- Convert absolute value to binary (add 0.5 for round-to-nearest)
        temp_val := abs_val + 0.5;
        for i in FP_TOTAL_BITS - 2 downto 0 loop
            bit_weight := 2.0 ** i;
            if temp_val >= bit_weight then
                result(i) := '1';
                temp_val := temp_val - bit_weight;
            end if;
        end loop;
        
        -- Apply two's complement if negative
        if is_negative then
            -- Invert all bits
            for i in result'range loop
                result(i) := not result(i);
            end loop;
            
            -- Add 1 (two's complement)
            for i in 0 to FP_TOTAL_BITS - 1 loop
                if result(i) = '0' then
                    result(i) := '1';
                    exit;
                else
                    result(i) := '0';
                end if;
            end loop;
        end if;

        return result;

    end function to_fp_frac;

    function to_fp (val : real) return fixed_point_data_t is
    begin
        return to_fp_frac(val, FP_FRACTION_BITS);
    end function to_fp;

    function to_fp_coeff (val : real) return fixed_point_data_t is
    begin
        return to_fp_frac(val, COEFF_FRACTION_BITS);
    end function to_fp_coeff;

End package body;