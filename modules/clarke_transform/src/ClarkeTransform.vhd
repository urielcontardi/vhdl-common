--! \file		ClarkeTransform.vhd
--!
--! \brief      Implements the Clarke Transform for three-phase systems.
--!             Calculates the components:
--!                 - X_alpha = (2/3) × (Xa - 0.5×Xb - 0.5×Xc)
--!                 - X_beta  = (1/√3) × (Xb - Xc)
--!                 - X_zero  = (1/3) × (Xa + Xb + Xc)
--!             All operations are performed in fixed-point (two's complement).
--!
--!             PIPELINE (6 stages, 5-cycle input-to-output latency):
--!               Stage 0: register inputs  (a_reg, b_reg, c_reg)
--!               Stage 1: compute sums     (alphaSum, betaSum, zeroSum)
--!               Stage 2: re-register sums (alphaSum_r, betaSum_r, zeroSum_r)
--!                        — retimeable register absorbed into DSP AREG=1 by
--!                          Vivado synthesis retiming (-retiming flag).
--!               Stage 3: multiply         (dsp_alpha_m = COEFF × sum_r)
--!                        — retimeable register absorbed into DSP MREG=1.
--!               Stage 4: P-register       (alpha, beta, zero)
--!               Stage 5: output register  (alpha_o, beta_o, zero_o)
--!
--!             Latency: 5 clock cycles from data_valid_i to data_valid_o.
--!             The extra Stage 2 register breaks the critical path: it gives
--!             Vivado retiming candidates to absorb into DSP AREG/MREG, which
--!             is essential for timing closure at 200 MHz on Zynq-7010 (-1).
--!             For wide (42×43-bit) multiplications Vivado uses a multi-DSP
--!             cascade; without AREG+MREG the combinatorial cascade path
--!             exceeds 5 ns (200 MHz period). Synthesis requires -retiming.
--!
--! \author		Uriel Abe Contardi (urielcontardi@hotmail.com)
--! \author		Vinícius de Carvalho Monteiro Longo (longo.vinicius@gmail.com)
--! \date       06-06-2025
--!
--! \version    1.4
--!
--! \note		Target devices : No specific target
--! \note		Tool versions  : Vivado 2020+ (requires synth_design -retiming)
--! \note		Dependencies   : No specific dependencies
--!
--! \ingroup	None
--! \warning	None
--!
--! \note		Revisions:
--!				- 1.0	06-06-2025	<urielcontardi@hotmail.com>
--!				- 1.1	06-08-2025	<longo.vinicius@gmail.com>
--!				- 1.2	2026-04-05	<urielcontardi@hotmail.com>  Explicit DSP48E1 (deprecated)
--!				- 1.3	2026-04-05	<urielcontardi@hotmail.com>
--!				  Behavioral multiplication; Vivado auto-infers DSP48E1. Fixes B-port
--!				  overflow and pipeline mismatch from v1.2. 4-cycle latency.
--!				- 1.4	2026-04-05	<urielcontardi@hotmail.com>
--!				  Added Stage 2 sum re-register to allow Vivado retiming to absorb
--!				  sums into DSP AREG=1 and multiply result into DSP MREG=1, achieving
--!				  timing closure at 200 MHz. Latency increased to 5 cycles.
--------------------------------------------------------------------------
-- Default libraries
--------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
--------------------------------------------------------------------------
-- User packages
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- Entity declaration
--------------------------------------------------------------------------
Entity ClarkeTransform is
    Generic (
        DATA_WIDTH : integer := 32;
        FRAC_WIDTH : integer := 16
    );
    Port (
        sysclk          : in std_logic;
        reset_n         : in std_logic;

        -- data_valid_o is asserted 5 clock cycles after data_valid_i
        data_valid_i    : in std_logic;

        --  ABC Input (two's complement, fixed point)
        a_in            : in  signed(DATA_WIDTH-1 downto 0);
        b_in            : in  signed(DATA_WIDTH-1 downto 0);
        c_in            : in  signed(DATA_WIDTH-1 downto 0);

        --  Alpha-Beta Output (two's complement, fixed point)
        alpha_o         : out signed(DATA_WIDTH-1 downto 0);
        beta_o          : out signed(DATA_WIDTH-1 downto 0);
        zero_o          : out signed(DATA_WIDTH-1 downto 0);
        data_valid_o    : out std_logic

    );
End entity;

--------------------------------------------------------------------------
-- Architecture
--------------------------------------------------------------------------
Architecture rtl of ClarkeTransform is

    -- Synthesis attributes: hint Vivado to use DSP primitives for multiply
    -- signals and allow retiming to absorb surrounding registers into DSP
    -- AREG/BREG and MREG for timing closure at 200 MHz.
    attribute use_dsp : string;

    -- Constants (calculated for fixed point representation)
    constant COEFF_2_3     : signed(DATA_WIDTH-1 downto 0) := to_signed(integer(2.0/3.0 * real(2**FRAC_WIDTH)), DATA_WIDTH);  -- 2/3
    constant COEFF_1_SQRT3 : signed(DATA_WIDTH-1 downto 0) := to_signed(integer(1.0/1.732050808 * real(2**FRAC_WIDTH)), DATA_WIDTH); -- 1/√3
    constant COEFF_1_3     : signed(DATA_WIDTH-1 downto 0) := to_signed(integer(1.0/3.0 * real(2**FRAC_WIDTH)), DATA_WIDTH);  -- 1/3

    -- Input Signals
    signal a : signed(DATA_WIDTH - 1 downto 0);
    signal b : signed(DATA_WIDTH - 1 downto 0);
    signal c : signed(DATA_WIDTH - 1 downto 0);

    -- Stage 0: input registers
    signal a_reg        : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal b_reg        : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal c_reg        : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    -- Stage 1: pre-multiply sums
    signal alphaSum     : signed(DATA_WIDTH downto 0);   -- 1 extra bit for overflow
    signal betaSum      : signed(DATA_WIDTH downto 0);
    signal zeroSum      : signed(DATA_WIDTH+1 downto 0); -- 2 extra bits for overflow

    -- Stage 2: re-registered sums (retimeable → absorbed into DSP AREG=1)
    signal alphaSum_r   : signed(DATA_WIDTH downto 0)   := (others => '0');
    signal betaSum_r    : signed(DATA_WIDTH downto 0)   := (others => '0');
    signal zeroSum_r    : signed(DATA_WIDTH+1 downto 0) := (others => '0');

    -- Stage 3: multiply (retimeable → absorbed into DSP MREG=1)
    signal dsp_alpha_m  : signed(2*DATA_WIDTH downto 0);
    signal dsp_beta_m   : signed(2*DATA_WIDTH downto 0);
    signal dsp_zero_m   : signed(2*DATA_WIDTH+1 downto 0);
    attribute use_dsp of dsp_alpha_m : signal is "yes";
    attribute use_dsp of dsp_beta_m  : signal is "yes";
    attribute use_dsp of dsp_zero_m  : signal is "yes";

    -- Stage 4: P-register
    signal alpha        : signed(2*DATA_WIDTH downto 0);
    signal beta         : signed(2*DATA_WIDTH downto 0);
    signal zero         : signed(2*DATA_WIDTH+1 downto 0);

    -- Pipeline valid tracking (5 bits → 5-cycle latency)
    --   bit 0: inputs registered        (Stage 0 → Stage 1)
    --   bit 1: sums registered          (Stage 1 → Stage 2)
    --   bit 2: sums re-registered       (Stage 2 → Stage 3)
    --   bit 3: multiply registered      (Stage 3 → Stage 4)
    --   bit 4: P-register registered    (Stage 4 → Stage 5 output)
    signal validReg     : std_logic_vector(4 downto 0) := (others => '0');

Begin

    --------------------------------------------------------------------------
    -- Internal Signals
    --------------------------------------------------------------------------
    a <= signed(a_in);
    b <= signed(b_in);
    c <= signed(c_in);

    --------------------------------------------------------------------------
    -- Process: Clarke Transform  (6-stage pipeline, 5-cycle latency)
    --------------------------------------------------------------------------
    Process(sysclk, reset_n)
        variable b_half, c_half : signed(DATA_WIDTH-1 downto 0);
    Begin
        if reset_n = '0' then

            a_reg        <= (others => '0');
            b_reg        <= (others => '0');
            c_reg        <= (others => '0');
            alphaSum     <= (others => '0');
            betaSum      <= (others => '0');
            zeroSum      <= (others => '0');
            alphaSum_r   <= (others => '0');
            betaSum_r    <= (others => '0');
            zeroSum_r    <= (others => '0');
            dsp_alpha_m  <= (others => '0');
            dsp_beta_m   <= (others => '0');
            dsp_zero_m   <= (others => '0');
            alpha        <= (others => '0');
            beta         <= (others => '0');
            zero         <= (others => '0');
            validReg     <= (others => '0');
            alpha_o      <= (others => '0');
            beta_o       <= (others => '0');
            zero_o       <= (others => '0');
            data_valid_o <= '0';

        elsif rising_edge(sysclk) then

            -- Pipeline valid tracking (shift register)
            validReg <= validReg(3 downto 0) & data_valid_i;

            -- Stage 0: register inputs
            a_reg <= a;
            b_reg <= b;
            c_reg <= c;

            -- Stage 1: compute sums from registered inputs
            b_half := shift_right(b_reg, 1);
            c_half := shift_right(c_reg, 1);
            alphaSum <= resize(a_reg, DATA_WIDTH+1) - resize(b_half, DATA_WIDTH+1) - resize(c_half, DATA_WIDTH+1);
            betaSum  <= resize(b_reg, DATA_WIDTH+1) - resize(c_reg, DATA_WIDTH+1);
            zeroSum  <= resize(a_reg, DATA_WIDTH+2) + resize(b_reg, DATA_WIDTH+2) + resize(c_reg, DATA_WIDTH+2);

            -- Stage 2: re-register sums
            -- These are pure register copies feeding the multiply.
            -- Vivado synthesis retiming (-retiming) absorbs these registers
            -- into the DSP48E1 A/B input registers (AREG=1), removing the
            -- sum-register-to-DSP route delay from the critical path.
            alphaSum_r <= alphaSum;
            betaSum_r  <= betaSum;
            zeroSum_r  <= zeroSum;

            -- Stage 3: multiply (behavioral — Vivado infers multi-DSP cascade)
            -- With retiming: alphaSum_r absorbed into DSP AREG, result into MREG.
            dsp_alpha_m <= COEFF_2_3     * alphaSum_r;
            dsp_beta_m  <= COEFF_1_SQRT3 * betaSum_r;
            dsp_zero_m  <= COEFF_1_3     * zeroSum_r;

            -- Stage 4: P-register
            alpha <= dsp_alpha_m;
            beta  <= dsp_beta_m;
            zero  <= dsp_zero_m;

            -- Stage 5: extract output bits and output valid
            alpha_o      <= alpha(FRAC_WIDTH + DATA_WIDTH - 1 downto FRAC_WIDTH);
            beta_o       <= beta(FRAC_WIDTH + DATA_WIDTH - 1 downto FRAC_WIDTH);
            zero_o       <= zero(FRAC_WIDTH + DATA_WIDTH - 1 downto FRAC_WIDTH);
            data_valid_o <= validReg(4);

        End if;
    End process;

End architecture;
