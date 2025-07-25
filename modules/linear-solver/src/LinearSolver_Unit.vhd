--! \file		LinearSolver_Unit.vhd
--!
--! \brief		stateResult_o = A*X + B*U
--!
--! \author		Uriel Abe Contardi (urielcontardi@hotmail.com)
--! \author		Vinícius de Carvalho Monteiro Longo (longo.vinicius@gmail.com)
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
--!             - 1.1   15-07-2025  <longo.vinicius@gmail.com>
--------------------------------------------------------------------------
-- Default libraries
--------------------------------------------------------------------------
Library ieee;
Use ieee.std_logic_1164.all;
Use ieee.numeric_std.all;

--------------------------------------------------------------------------
-- User packages
--------------------------------------------------------------------------
use work.Solver_pkg.all;

--------------------------------------------------------------------------
-- Entity declaration
--------------------------------------------------------------------------
Entity LinearSolver_Unit is
    generic (
        N_SS    : natural := 5;    -- Number of State Space
        N_IN    : natural := 2     -- Inputs number of State Space
    );
    Port (
        sysclk          : in std_logic;
        start_i         : in std_logic;

        Avec_i          : in vector_fp_t(0 to N_SS - 1);
        Xvec_i          : in vector_fp_t(0 to N_SS - 1);
        Bvec_i          : in vector_fp_t(0 to N_IN - 1);
        Uvec_i          : in vector_fp_t(0 to N_IN - 1);

        stateResult_o   : out fixed_point_data_t;
        busy_o          : out std_logic
    );
End entity;

--------------------------------------------------------------------------
-- Architecture
--------------------------------------------------------------------------
Architecture rtl of LinearSolver_Unit is
    
    constant TOTAL_OPERATIONS   : integer := N_SS+N_IN;
    constant MULTIPLIER_DELAY   : integer := 7;

    -- Handle Input to do logi
    signal operand_1_vec        : vector_fp_t(0 to TOTAL_OPERATIONS - 1);
    signal operand_2_vec        : vector_fp_t(0 to TOTAL_OPERATIONS - 1);

    -- Sequencer
    signal index                : integer range 0 to TOTAL_OPERATIONS;
    signal data_valid           : std_logic := '0';  

    -- Multiplier Signals
    signal pipeline_mult        : std_logic_vector(MULTIPLIER_DELAY - 1 downto 0) := (others => '0');
    signal operand_1, operand_2 : fixed_point_data_t;
    signal product              : std_logic_vector((FP_TOTAL_BITS*2)-1 downto 0);
    
    -- Accumulator
    signal acmtr                : std_logic_vector((FP_TOTAL_BITS*2)-1 downto 0) := (others => '0');

    --------------------------------------------------------------------------
    -- Components
    --------------------------------------------------------------------------
    component mult_gen_0
    port (
      CLK   : in STD_LOGIC;
      A     : in STD_LOGIC_VECTOR(FP_TOTAL_BITS-1 downto 0);
      B     : in STD_LOGIC_VECTOR(FP_TOTAL_BITS-1 downto 0);
      P     : out STD_LOGIC_VECTOR((FP_TOTAL_BITS*2)-1 downto 0)
    );
    end component;

Begin

    --------------------------------------------------------------------------
    -- Assign Output
    --------------------------------------------------------------------------
    busy_o      <= '1' when pipeline_mult /= (pipeline_mult'range => '0') or start_i = '1' or data_valid = '1' else '0';
    stateResult_o <= acmtr(FP_TOTAL_BITS + FP_FRACTION_BITS - 1 downto FP_FRACTION_BITS);

    --------------------------------------------------------------------------
    -- Internal Signals
    --------------------------------------------------------------------------
    operand_1_vec(0 to N_SS - 1)  <= Avec_i;
    operand_1_vec(N_SS to TOTAL_OPERATIONS - 1) <= Bvec_i;

    operand_2_vec(0 to N_SS - 1)  <= Xvec_i;
    operand_2_vec(N_SS to TOTAL_OPERATIONS - 1) <= Uvec_i;
    
    --------------------------------------------------------------------------
    -- Multiplier
    -- Note: DSP48 Xilinx IP, optimum pipeline 6
    --------------------------------------------------------------------------
    Multiplier : mult_gen_0
    port map (
        CLK => sysclk,
        A => operand_1,
        B => operand_2,
        P => product
    );

    operand_1    <= operand_1_vec(index);
    operand_2    <= operand_2_vec(index);
    
    --------------------------------------------------------------------------
    -- Sequencer
    --------------------------------------------------------------------------
    process(sysclk)
    begin
        if rising_edge(sysclk) then                
            if start_i = '1' then
                index <= 0;
                data_valid <= '1';
            elsif data_valid = '1' and index < TOTAL_OPERATIONS -1 then
                index <= index + 1;
            else
                data_valid <= '0';
            end if;

            -- -- Pipeline Multiplier
            pipeline_mult <= pipeline_mult(pipeline_mult'left - 1 downto 0) & data_valid;

            -- Product adder
            if start_i = '1' then
                acmtr <= (others => '0');
            elsif pipeline_mult(pipeline_mult'left) = '1' then
                acmtr <= std_logic_vector(signed(acmtr) + signed(product));
            end if;
                    
        end if;
    end process;

End architecture;