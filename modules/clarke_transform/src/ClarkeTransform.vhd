--! \file		ClarkeTransform.vhd
--!
--! \brief      Implements the Clarke Transform for three-phase systems.
--!             Calculates the components:
--!                 - X_alpha = (2/3) × (Xa - 0.5×Xb - 0.5×Xc)
--!                 - X_beta  = (1/√3) × (Xb - Xc)
--!                 - X_zero  = (1/3) × (Xa + Xb + Xc)
--!             All operations are performed in fixed-point (two's complement).
--!
--!             PIPELINE:
--!               Stage 0: register inputs  (a_reg, b_reg, c_reg)
--!               Stage 1: compute sums     (alphaSum, betaSum)
--!               Stage 2: re-register sums (alphaSum_r, betaSum_r)
--!               Stage 3: pipelined mult_gen DSPs (MULT_LATENCY = 7)
--!               Stage 4: product register  (alpha, beta)
--!               Stage 5: output register   (alpha_o, beta_o, zero_o)
--!
--!             data_valid_o follows data_valid_i through VALID_WIDTH clocks
--!             (11 clocks with the current 7-cycle mult_gen IP plus local
--!             pipeline registers). With data_valid_i tied high, the block
--!             streams one transformed sample per clock after the pipeline fill.
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

        -- data_valid_o follows data_valid_i after VALID_WIDTH clock cycles
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

    -- Constants (calculated for fixed point representation). The values are
    -- positive and smaller than 1.0, so FRAC_WIDTH+1 bits are sufficient and
    -- avoid unnecessarily wide 42x43 DSP cascades at 200 MHz.
    constant COEFF_WIDTH   : integer := FRAC_WIDTH + 1;
    constant COEFF_2_3     : signed(COEFF_WIDTH-1 downto 0) := to_signed(integer(2.0/3.0 * real(2**FRAC_WIDTH)), COEFF_WIDTH);  -- 2/3
    constant COEFF_1_SQRT3 : signed(COEFF_WIDTH-1 downto 0) := to_signed(integer(1.0/1.732050808 * real(2**FRAC_WIDTH)), COEFF_WIDTH); -- 1/sqrt(3)

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

    -- Stage 2: re-registered sums (retimeable → absorbed into DSP AREG=1)
    signal alphaSum_r   : signed(DATA_WIDTH downto 0)   := (others => '0');
    signal betaSum_r    : signed(DATA_WIDTH downto 0)   := (others => '0');

    constant PRODUCT_WIDTH : integer := DATA_WIDTH + 1 + COEFF_WIDTH;
    constant MULT_LATENCY  : integer := 7;
    constant VALID_WIDTH   : integer := MULT_LATENCY + 4;

    component ClarkeMultiplier_DSP
    port (
        CLK : in  std_logic;
        A   : in  std_logic_vector(DATA_WIDTH downto 0);
        B   : in  std_logic_vector(COEFF_WIDTH-1 downto 0);
        P   : out std_logic_vector(PRODUCT_WIDTH-1 downto 0)
    );
    end component;

    -- Stage 3: pipeline DSP multipliers generated as mult_gen IP. This avoids
    -- Vivado inferring an unregistered PCOUT->PCIN cascade for 43x29 constants.
    signal alpha_prod_slv : std_logic_vector(PRODUCT_WIDTH-1 downto 0);
    signal beta_prod_slv  : std_logic_vector(PRODUCT_WIDTH-1 downto 0);
    signal alpha_prod     : signed(PRODUCT_WIDTH-1 downto 0);
    signal beta_prod      : signed(PRODUCT_WIDTH-1 downto 0);

    -- Stage 4: output register
    signal alpha        : signed(PRODUCT_WIDTH-1 downto 0);
    signal beta         : signed(PRODUCT_WIDTH-1 downto 0);

    signal validReg     : std_logic_vector(VALID_WIDTH-1 downto 0) := (others => '0');

Begin

    alpha_prod <= signed(alpha_prod_slv);
    beta_prod  <= signed(beta_prod_slv);

    AlphaMultiplier : ClarkeMultiplier_DSP
    port map (
        CLK => sysclk,
        A   => std_logic_vector(alphaSum_r),
        B   => std_logic_vector(COEFF_2_3),
        P   => alpha_prod_slv
    );

    BetaMultiplier : ClarkeMultiplier_DSP
    port map (
        CLK => sysclk,
        A   => std_logic_vector(betaSum_r),
        B   => std_logic_vector(COEFF_1_SQRT3),
        P   => beta_prod_slv
    );

    --------------------------------------------------------------------------
    -- Internal Signals
    --------------------------------------------------------------------------
    a <= signed(a_in);
    b <= signed(b_in);
    c <= signed(c_in);

    --------------------------------------------------------------------------
    -- Process: Clarke Transform  (streaming DSP pipeline)
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
            alphaSum_r   <= (others => '0');
            betaSum_r    <= (others => '0');
            alpha        <= (others => '0');
            beta         <= (others => '0');
            validReg     <= (others => '0');
            alpha_o      <= (others => '0');
            beta_o       <= (others => '0');
            zero_o       <= (others => '0');
            data_valid_o <= '0';

        elsif rising_edge(sysclk) then

            -- Pipeline valid tracking (shift register)
            validReg <= validReg(VALID_WIDTH-2 downto 0) & data_valid_i;

            -- Stage 0: register inputs
            a_reg <= a;
            b_reg <= b;
            c_reg <= c;

            -- Stage 1: compute sums from registered inputs
            b_half := shift_right(b_reg, 1);
            c_half := shift_right(c_reg, 1);
            alphaSum <= resize(a_reg, DATA_WIDTH+1) - resize(b_half, DATA_WIDTH+1) - resize(c_half, DATA_WIDTH+1);
            betaSum  <= resize(b_reg, DATA_WIDTH+1) - resize(c_reg, DATA_WIDTH+1);

            -- Stage 2: re-register sums
            -- These are pure register copies feeding the multiply.
            -- Vivado synthesis retiming (-retiming) absorbs these registers
            -- into the DSP48E1 A/B input registers (AREG=1), removing the
            -- sum-register-to-DSP route delay from the critical path.
            alphaSum_r <= alphaSum;
            betaSum_r  <= betaSum;

            -- Stage 4: output register after pipelined multiplier IPs.
            alpha <= alpha_prod;
            beta  <= beta_prod;

            -- Stage 5: extract output bits and delayed output valid
            alpha_o      <= alpha(FRAC_WIDTH + DATA_WIDTH - 1 downto FRAC_WIDTH);
            beta_o       <= beta(FRAC_WIDTH + DATA_WIDTH - 1 downto FRAC_WIDTH);
            zero_o       <= (others => '0');
            data_valid_o <= validReg(VALID_WIDTH-1);

        End if;
    End process;

End architecture;
