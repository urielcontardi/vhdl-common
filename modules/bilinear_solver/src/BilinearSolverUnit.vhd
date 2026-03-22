--! \file		BilinearSolverUnit.vhd
--!
--! \brief		stateResult_o = (X * X_Y) * A + B * U
--!
--!             Two-stage multiply pipeline:
--!               Stage 1 (Multiplier1): product1 = X[i] * X[Y[i]]
--!                 Both operands are state variables (large magnitude) so the
--!                 Q14.28 intermediate product does not underflow.
--!               Stage 2 (Multiplier2): product2 = product1 * A[i]
--!                 The small coefficient A[i] is applied last, in the full
--!                 84-bit accumulator domain before final extraction.
--!
--!             Y acts as an index selector for the second state operand.
--!             Set Y[i] < 0 to disable the bilinear coupling for row i
--!             (operand2 defaults to FIXED_POINT_ONE, so result = X[i] * A[i]).
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
Entity BilinearSolverUnit is
    Generic (
        N_SS    : natural := 5;    -- Number of State Space
        N_IN    : natural := 2     -- Inputs number of State Space
    );
    Port (
        sysclk          : in std_logic;
        start_i         : in std_logic;

        Avec_i          : in vector_fp_t(0 to N_SS - 1);
        Xvec_i          : in vector_fp_t(0 to N_SS - 1);
        Yvec_i          : in vector_fp_t(0 to N_SS - 1);

        Bvec_i          : in vector_fp_t(0 to N_IN - 1);
        Uvec_i          : in vector_fp_t(0 to N_IN - 1);

        stateResult_o   : out fixed_point_data_t;
        busy_o          : out std_logic
    );
End entity;

--------------------------------------------------------------------------
-- Architecture
--------------------------------------------------------------------------
Architecture rtl of BilinearSolverUnit is

    constant TOTAL_OPERATIONS   : integer := N_SS+N_IN;
    constant MULTIPLIER_DELAY   : integer := 7;
    constant FIXED_POINT_ONE    : fixed_point_data_t := std_logic_vector(to_signed(2**FP_FRACTION_BITS, FP_TOTAL_BITS));

    -- Handle Input to do logic
    signal operand1_vec         : vector_fp_t(0 to TOTAL_OPERATIONS - 1);
    signal operand2_vec         : vector_fp_t(0 to TOTAL_OPERATIONS - 1);
    signal operand3_vec         : vector_fp_t(0 to TOTAL_OPERATIONS - 1);
    signal operand1             : fixed_point_data_t;
    signal operand2             : fixed_point_data_t;
    signal operand3             : fixed_point_data_t;

    -- Sequencer
    signal pipeline1            : std_logic_vector(MULTIPLIER_DELAY - 1 downto 0) := (others => '0');
    signal pipeline2            : std_logic_vector(MULTIPLIER_DELAY - 1 downto 0) := (others => '0');
    signal index1               : integer range 0 to TOTAL_OPERATIONS;
    signal index2               : integer range 0 to TOTAL_OPERATIONS;
    signal pipeline3_tgr        : std_logic := '0';
    signal busy                 : std_logic := '0';

    -- Multiplier Signals
    signal product1_raw         : std_logic_vector((2*FP_TOTAL_BITS)-1 downto 0);
    signal product1_rounded     : std_logic_vector((2*FP_TOTAL_BITS)-1 downto 0);
    signal product1             : fixed_point_data_t;
    signal product2_raw         : std_logic_vector((2*FP_TOTAL_BITS)-1 downto 0);

    -- Round-to-nearest constant: 2^(FP_FRACTION_BITS-1) in the Q28.56 accumulator domain
    -- Adding this half-LSB before truncation eliminates systematic floor bias
    constant ROUND_HALF_P1  : signed((2*FP_TOTAL_BITS)-1 downto 0) :=
        to_signed(2**(FP_FRACTION_BITS-1), 2*FP_TOTAL_BITS);   -- 2^27 (half-LSB for product1)
    constant ROUND_HALF_P2  : signed((2*FP_TOTAL_BITS)-1 downto 0) :=
        to_signed(2**(FP_FRACTION_BITS-1), 2*FP_TOTAL_BITS);   -- 2^27 (half-LSB for product2)

    -- Accumulator
    signal acmtr                : std_logic_vector((2*FP_TOTAL_BITS)-1 downto 0) := (others => '0');
    signal acmtr_rounded        : std_logic_vector((2*FP_TOTAL_BITS)-1 downto 0);

    --------------------------------------------------------------------------
    -- Component Declaration
    -- Note: This component is a DSP48 IP core from Xilinx
    --------------------------------------------------------------------------
    component BilienarSolverUnit_DSP
    port (
        CLK : in std_logic;
        A   : in std_logic_vector(FP_TOTAL_BITS - 1 downto 0);
        B   : in std_logic_vector(FP_TOTAL_BITS - 1 downto 0);
        P   : out std_logic_vector((2*FP_TOTAL_BITS)-1 downto 0)
    );
    end component;

Begin

    --------------------------------------------------------------------------
    -- Assign Output
    -- Round-to-nearest: add half-LSB before truncating accumulator to Q14.28
    --------------------------------------------------------------------------
    acmtr_rounded <= std_logic_vector(signed(acmtr) + ROUND_HALF_P2);
    stateResult_o <= acmtr_rounded(FP_TOTAL_BITS + FP_FRACTION_BITS - 1 downto FP_FRACTION_BITS);
    busy_o        <= busy;

    --------------------------------------------------------------------------
    -- Internal Signals
    -- Each operand vector is driven by a single process to avoid mixed-driver
    -- issues (process + concurrent slice) in GHDL simulation.
    --------------------------------------------------------------------------

    -- Stage 1 operands: X[i] (state) or B[j] (input coefficient)
    Operand1Assign : process(Xvec_i, Bvec_i)
    begin
        for i in 0 to N_SS - 1 loop
            operand1_vec(i) <= Xvec_i(i);
        end loop;
        for j in 0 to N_IN - 1 loop
            operand1_vec(N_SS + j) <= Bvec_i(j);
        end loop;
    end process;

    -- Stage 1 second operand: X[Y[i]] for state rows, U[j] for input rows
    YVec : process (Yvec_i, Xvec_i, Uvec_i)
        variable index : integer range 0 to N_SS - 1;
    begin
        for aa in 0 to N_SS - 1 loop
            -- Y[i] < 0 means no bilinear coupling: operand2 = 1 so product1 = X[i]
            -- Guard against metavalue ('U'/'X') during initialization.
            if is_x(Yvec_i(aa)) or Yvec_i(aa)(FP_TOTAL_BITS - 1) = '1' then
                operand2_vec(aa) <= FIXED_POINT_ONE;
            else
                index := to_integer(signed(Yvec_i(aa)));
                operand2_vec(aa) <= Xvec_i(index);
            end if;
        end loop;
        for j in 0 to N_IN - 1 loop
            operand2_vec(N_SS + j) <= Uvec_i(j);
        end loop;
    end process;

    -- Stage 2 operands: A[i] for state rows (applied last, in 84-bit domain),
    -- FIXED_POINT_ONE for input rows (B*U already complete after stage 1).
    Operand3Assign : process(Avec_i)
    begin
        for i in 0 to N_SS - 1 loop
            operand3_vec(i) <= Avec_i(i);
        end loop;
        for i in N_SS to TOTAL_OPERATIONS - 1 loop
            operand3_vec(i) <= FIXED_POINT_ONE;
        end loop;
    end process;
    
    --------------------------------------------------------------------------
    -- Multiplier
    --------------------------------------------------------------------------
    Multiplier1 : BilienarSolverUnit_DSP
    port map (
        CLK => sysclk,
        A => operand1,
        B => operand2,
        P => product1_raw
    );
    
    operand1        <= operand1_vec(index1);
    operand2        <= operand2_vec(index1);
    -- Round-to-nearest: add half-LSB (2^27) before discarding the fractional bits
    product1_rounded <= std_logic_vector(signed(product1_raw) + ROUND_HALF_P1);
    product1         <= product1_rounded(FP_TOTAL_BITS + FP_FRACTION_BITS - 1 downto FP_FRACTION_BITS);
    
    Multiplier2 : BilienarSolverUnit_DSP
    port map (
        CLK => sysclk,
        A => product1,
        B => operand3,
        P => product2_raw
    );

    operand3    <= operand3_vec(index2);

    --------------------------------------------------------------------------
    -- Sequencer
    --------------------------------------------------------------------------
    process(sysclk)
        variable pipeline1_tgr  : std_Logic := '0';
        variable pipeline2_tgr  : std_Logic := '0';
    begin
        if rising_edge(sysclk) then
            
            --------------------------------------------------------------------------
            -- Pipeline Trigger
            --------------------------------------------------------------------------
            if start_i = '1' and busy = '0' then
                pipeline1_tgr   := '1';
            elsif index1 = TOTAL_OPERATIONS - 1 then
                pipeline1_tgr   := '0';
            end if;

            --------------------------------------------------------------------------
            -- 1. First pipeline stage
            -- operand1 and operand2 multiplication
            --------------------------------------------------------------------------
            -- Pipeline
            pipeline1 <= pipeline1(pipeline1'left - 1 downto 0) & pipeline1_tgr;

            if pipeline1(pipeline1'right) = '1' AND index1 < TOTAL_OPERATIONS - 1 then
                index1 <= index1 + 1;
            else
                index1 <= 0;
            end if;
            
            --------------------------------------------------------------------------
            -- 2. Second pipeline stage
            -- product1 and operand3 multiplication
            --------------------------------------------------------------------------
            pipeline2_tgr := pipeline1(pipeline1'left);
            pipeline2 <= pipeline2(pipeline2'left - 1 downto 0) & pipeline2_tgr;

            if pipeline2(pipeline2'right) = '1' AND index2 < TOTAL_OPERATIONS - 1 then
                index2 <= index2 + 1;
            else
                index2 <= 0;
            end if;
            
            --------------------------------------------------------------------------
            -- 3. Third stage: Accumulator
            --------------------------------------------------------------------------
            pipeline3_tgr <= pipeline2(pipeline2'left);
            if start_i = '1' and busy = '0' then
                acmtr <= (others => '0');
            elsif pipeline3_tgr = '1' then
                acmtr <= std_logic_vector(signed(acmtr) + signed(product2_raw));
            end if;

            --------------------------------------------------------------------------
            -- Busy Signal
            --------------------------------------------------------------------------
            if start_i = '1' then
                busy <= '1';
            elsif  pipeline1 = (pipeline1'range => '0') AND
                    pipeline2 = (pipeline2'range => '0') AND
                    pipeline3_tgr = '0' then
                busy <= '0';
            end if;

        end if;
    end process;

End architecture;
