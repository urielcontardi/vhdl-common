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
    constant MULTIPLIER_DELAY   : integer := 8;
    constant FIXED_POINT_ONE    : fixed_point_data_t := std_logic_vector(to_signed(2**FP_FRACTION_BITS, FP_TOTAL_BITS));

    -- Handle Input to do logic
    signal operand1_vec         : vector_fp_t(0 to TOTAL_OPERATIONS - 1);
    signal operand2_vec         : vector_fp_t(0 to TOTAL_OPERATIONS - 1);
    signal operand3_vec         : vector_fp_t(0 to TOTAL_OPERATIONS - 1);
    signal operand1             : fixed_point_data_t := (others => '0');
    signal operand2             : fixed_point_data_t := (others => '0');
    signal operand3_mux         : fixed_point_data_t;

    -- Sequencer
    signal pipeline1            : std_logic_vector(MULTIPLIER_DELAY - 1 downto 0) := (others => '0');
    signal pipeline2            : std_logic_vector(MULTIPLIER_DELAY - 1 downto 0) := (others => '0');
    signal index1               : integer range 0 to TOTAL_OPERATIONS := 0;
    signal index2               : integer range 0 to TOTAL_OPERATIONS := 0;
    signal pipeline3_tgr        : std_logic := '0';
    signal result_latch_pending : std_logic := '0';
    signal busy                 : std_logic := '0';

    -- Multiplier Signals
    signal product1_raw         : std_logic_vector((2*FP_TOTAL_BITS)-1 downto 0);
    signal product1_rounded     : std_logic_vector((2*FP_TOTAL_BITS)-1 downto 0);
    signal product1             : fixed_point_data_t;
    signal product2_raw         : std_logic_vector((2*FP_TOTAL_BITS)-1 downto 0);

    -- Stage 1 multiplies state x state (both Q14.28) -> rescale by FP_FRACTION_BITS.
    -- Built with shift_left rather than 2**n: the exponent can exceed the range
    -- of VHDL's integer (2**31-1) once the coefficient format widens.
    constant ROUND_HALF_P1  : signed((2*FP_TOTAL_BITS)-1 downto 0) :=
        shift_left(to_signed(1, 2*FP_TOTAL_BITS), FP_FRACTION_BITS-1);
    -- Stage 2 multiplies that Q14.28 result by a coefficient in Q(COEFF_INTEGER).
    -- (COEFF_FRACTION), so the accumulator holds COEFF_FRACTION_BITS + 28
    -- fractional bits and must be rescaled by COEFF_FRACTION_BITS -- not 28.
    constant ROUND_HALF_P2  : signed((2*FP_TOTAL_BITS)-1 downto 0) :=
        shift_left(to_signed(1, 2*FP_TOTAL_BITS), COEFF_FRACTION_BITS-1);

    -- Accumulator
    signal acmtr                : std_logic_vector((2*FP_TOTAL_BITS)-1 downto 0) := (others => '0');
    signal stateResult_r       : fixed_point_data_t := (others => '0');

    -- start_i registered: it arrives late (solver_start depends on
    -- coeff_apply_pending) and driving an 84-bit mux from it costs ~0.8 ns of
    -- setup slack on the 200 MHz solver clock.
    signal start_pending        : std_logic := '0';
    -- Truncation remainder carried into the next step. Bounded by one output
    -- quantum, so COEFF_FRACTION_BITS+1 bits are enough -- keeping this narrow
    -- is what makes the start-time seed mux cheap.
    signal residual             : signed(COEFF_FRACTION_BITS downto 0) := (others => '0');

    -- Error feedback: the truncation remainder is left in acmtr itself (see the
    -- accumulator process). One step of the state increment is routinely smaller
    -- than the Q14.28 output quantum -- with Ts = 130 ns the per-step change of a
    -- state sits at the resolution floor, so plain truncation would emit the same
    -- rounded-down value every step, a systematic bias that integrates directly
    -- into the effective machine parameters. Carrying the remainder makes the sum
    -- of the emitted increments track the exact sum, turning the bias into a
    -- bounded, zero-mean ripple.

    --------------------------------------------------------------------------
    -- Component Declaration — Xilinx mult_gen IP (C_MULT_TYPE=1 → DSP48E1)
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

    operand3_mux <= operand3_vec(index2);

    --------------------------------------------------------------------------
    -- Assign Output — round-to-nearest before truncating accumulator to Q14.28
    --------------------------------------------------------------------------
    stateResult_o <= stateResult_r;
    busy_o        <= busy;

    --------------------------------------------------------------------------
    -- Internal Signals
    -- Each operand vector is driven by a single process to avoid mixed-driver
    -- issues (process + concurrent slice) in GHDL simulation.
    --------------------------------------------------------------------------

    -- Stage 1 operands: X[i] (state) or B[j] (input coefficient)
    Operand1Assign : process(Xvec_i, Uvec_i)
    begin
        for i in 0 to N_SS - 1 loop
            operand1_vec(i) <= Xvec_i(i);
        end loop;
        for j in 0 to N_IN - 1 loop
            operand1_vec(N_SS + j) <= Uvec_i(j);
        end loop;
    end process;

    -- Stage 1 second operand: X[Y[i]] for state rows, U[j] for input rows.
    -- Y is not a Q14.28 value; the TIM solver stores only raw selectors:
    --   MSB=1 -> disabled/linear term, low bits 0..4 -> X index.
    -- Decode those legal values explicitly. This avoids a 42-bit signed
    -- to_integer/index mux on the 200 MHz operand register path.
    YVec : process (Yvec_i, Xvec_i)
    begin
        for aa in 0 to N_SS - 1 loop
            if is_x(Yvec_i(aa)) or Yvec_i(aa)(FP_TOTAL_BITS - 1) = '1' then
                operand2_vec(aa) <= FIXED_POINT_ONE;
            else
                case Yvec_i(aa)(2 downto 0) is
                    when "000" => operand2_vec(aa) <= Xvec_i(0);
                    when "001" => operand2_vec(aa) <= Xvec_i(1);
                    when "010" => operand2_vec(aa) <= Xvec_i(2);
                    when "011" => operand2_vec(aa) <= Xvec_i(3);
                    when "100" => operand2_vec(aa) <= Xvec_i(4);
                    when others => operand2_vec(aa) <= FIXED_POINT_ONE;
                end case;
            end if;
        end loop;
        for j in 0 to N_IN - 1 loop
            operand2_vec(N_SS + j) <= FIXED_POINT_ONE;
        end loop;
    end process;

    -- Stage 2 operands: A[i] for state rows (applied last, in 84-bit domain),
    -- FIXED_POINT_ONE for input rows (B*U already complete after stage 1).
    -- Stage 3 operand: the coefficient. A[i] for state rows, B[j] for input
    -- rows. Both matrices enter here (and only here) so that a single rescale
    -- by COEFF_FRACTION_BITS at the accumulator serves every coefficient --
    -- stage 1 stays purely Q14.28 (state x state).
    Operand3Assign : process(Avec_i, Bvec_i)
    begin
        for i in 0 to N_SS - 1 loop
            operand3_vec(i) <= Avec_i(i);
        end loop;
        for j in 0 to N_IN - 1 loop
            operand3_vec(N_SS + j) <= Bvec_i(j);
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
    
    -- Registered operand selects keep the index/mux logic out of the DSP input timing path.
    product1_rounded <= std_logic_vector(signed(product1_raw) + ROUND_HALF_P1);
    product1         <= product1_rounded(FP_TOTAL_BITS + FP_FRACTION_BITS - 1 downto FP_FRACTION_BITS);

    Multiplier2 : BilienarSolverUnit_DSP
    port map (
        CLK => sysclk,
        A => product1,
        B => operand3_mux,
        P => product2_raw
    );


    --------------------------------------------------------------------------
    -- Sequencer
    --------------------------------------------------------------------------
    process(sysclk)
        variable pipeline1_tgr  : std_Logic := '0';
        variable pipeline2_tgr  : std_Logic := '0';
        variable sum_v          : signed((2*FP_TOTAL_BITS)-1 downto 0);
        variable rounded_v      : signed((2*FP_TOTAL_BITS)-1 downto 0);
        variable result_v       : signed(FP_TOTAL_BITS-1 downto 0);
    begin
        if rising_edge(sysclk) then
            operand1 <= operand1_vec(index1);
            operand2 <= operand2_vec(index1);

            
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
            -- Flush any partial sum left by a solve that never reached its
            -- latch. This unit has no reset port, so before the error-feedback
            -- change the clear-on-start was the ONLY path that could empty the
            -- accumulator -- and pwm_solver_reset_s is pulsed on every run and
            -- stop, which can abort a solve mid-accumulation. Without this the
            -- stale partial sum would corrupt every later step, permanently.
            --
            -- start_i is registered first: it arrives late (solver_start depends
            -- on coeff_apply_pending) and an 84-bit mux on it costs ~0.8 ns of
            -- setup slack. Clearing one cycle later is safe because the first
            -- product2 lands only after the multiplier pipeline drains.
            start_pending <= start_i and not busy;

            if start_pending = '1' then
                -- Seed from the residual register, not from acmtr: this both
                -- carries the error feedback AND discards any partial sum left
                -- behind by an aborted solve. residual is only 39 bits (it is
                -- bounded by one output quantum), so the mux stays small.
                acmtr <= std_logic_vector(resize(residual, 2*FP_TOTAL_BITS));
            elsif pipeline3_tgr = '1' then
                sum_v := signed(acmtr) + signed(product2_raw);
                acmtr <= std_logic_vector(sum_v);
            elsif result_latch_pending = '1' then
                -- One cycle past the last accumulation: emit and keep the rest.
                rounded_v := signed(acmtr) + ROUND_HALF_P2;
                result_v  := rounded_v(FP_TOTAL_BITS + COEFF_FRACTION_BITS - 1 downto COEFF_FRACTION_BITS);
                stateResult_r <= std_logic_vector(result_v);
                residual <= resize(signed(acmtr)
                            - shift_left(resize(result_v, 2*FP_TOTAL_BITS), COEFF_FRACTION_BITS),
                            COEFF_FRACTION_BITS + 1);
            end if;
            result_latch_pending <= pipeline3_tgr;

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
