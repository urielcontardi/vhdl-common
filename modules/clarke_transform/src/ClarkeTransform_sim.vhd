--! \file		ClarkeTransform_sim.vhd
--!
--! \brief      Simulation-friendly version of ClarkeTransform (no UNISIM dependency)
--!             Implements the Clarke Transform for three-phase systems.
--!             Calculates the components:
--!                 - X_alpha = (2/3) × (Xa - 0.5×Xb - 0.5×Xc)
--!                 - X_beta  = (1/√3) × (Xb - Xc)
--!                 - X_zero  = (1/3) × (Xa + Xb + Xc)
--!             All operations are performed in fixed-point (two's complement).
--!             Uses behavioral DSP48E1 equivalents (MREG=1) for GHDL simulation.
--!            
--! \author		Uriel Abe Contardi (urielcontardi@hotmail.com)
--! \author		Vinícius de Carvalho Monteiro Longo (longo.vinicius@gmail.com)
--! \date       2026-04-05
--!
--! \version    1.2-sim
--!
--! \note		This version is for simulation ONLY. Synthesis uses ClarkeTransform.vhd
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

        -- This is used to control the data flow and ensure that the outputs are valid
        -- data_valid_o will be '1' when the outputs are valid
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
    
    -- Constants (calculated for fixed point representation)
    constant COEFF_2_3     : signed(DATA_WIDTH-1 downto 0) := to_signed(integer(2.0/3.0 * real(2**FRAC_WIDTH)), DATA_WIDTH);  -- 2/3
    constant COEFF_1_SQRT3 : signed(DATA_WIDTH-1 downto 0) := to_signed(integer(1.0/1.732050808 * real(2**FRAC_WIDTH)), DATA_WIDTH); -- 1/√3
    constant COEFF_1_3     : signed(DATA_WIDTH-1 downto 0) := to_signed(integer(1.0/3.0 * real(2**FRAC_WIDTH)), DATA_WIDTH);  -- 1/3

    -- Input Signals
    signal a : signed(DATA_WIDTH - 1 downto 0);
    signal b : signed(DATA_WIDTH - 1 downto 0);
    signal c : signed(DATA_WIDTH - 1 downto 0);

    -- Alpha Signals
    signal alphaSum     : signed(DATA_WIDTH downto 0);  -- Extra bit for overflow
    signal alpha        : signed(2*DATA_WIDTH downto 0); 
    
    -- Beta Signals
    signal betaSum      : signed(DATA_WIDTH downto 0);
    signal beta         : signed(2*DATA_WIDTH downto 0); 
    
    -- Zero Signals
    signal zeroSum      : signed(DATA_WIDTH+1 downto 0); -- 2x Extra bit for overflow
    signal zero         : signed(2*DATA_WIDTH+1 downto 0);

    -- Behavioral DSP48E1 simulation signals (MREG=1 equivalent)
    signal dsp_alpha_m : signed(2*DATA_WIDTH downto 0);  -- M-register
    signal dsp_beta_m  : signed(2*DATA_WIDTH downto 0);
    signal dsp_zero_m  : signed(2*DATA_WIDTH+1 downto 0);
    
    -- Input register stage (breaks critical path for 200 MHz timing closure)
    signal a_reg        : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal b_reg        : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal c_reg        : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    -- Pipeline: 4 bits — DSP48E1 MREG adds 1 cycle
    --   bit 0: input registered  (stage 0 → stage 1)
    --   bit 1: sums registered   (stage 1 → stage 2)
    --   bit 2: DSP M-reg stage   (stage 2 → stage 3, MREG=1)
    --   bit 3: products ready    (stage 3 → output)
    signal validReg     : std_logic_vector(3 downto 0) := (others => '0');

Begin

    --------------------------------------------------------------------------
    -- Internal Signals
    --------------------------------------------------------------------------
    a <= signed(a_in);
    b <= signed(b_in);
    c <= signed(c_in);

    --------------------------------------------------------------------------
    -- Process: Clarke Transform  (4-stage pipeline with DSP48E1 MREG=1)
    --
    --  Stage 0: register inputs           a_reg, b_reg, c_reg
    --  Stage 1: compute sums              alphaSum, betaSum, zeroSum
    --  Stage 2: DSP48E1 M-register        (MREG=1 internal stage)
    --  Stage 3: DSP48E1 P-register        alpha, beta, zero
    --  Stage 4: extract output bits       alpha_o, beta_o, zero_o
    --
    -- Latency: 4 clock cycles from data_valid_i to data_valid_o.
    --------------------------------------------------------------------------
    Process(sysclk, reset_n)
        variable b_half, c_half     : signed(DATA_WIDTH-1 downto 0);
    Begin
        if reset_n = '0' then

            a_reg    <= (others => '0');
            b_reg    <= (others => '0');
            c_reg    <= (others => '0');
            alphaSum <= (others => '0');
            betaSum  <= (others => '0');
            zeroSum  <= (others => '0');
            dsp_alpha_m <= (others => '0');
            dsp_beta_m  <= (others => '0');
            dsp_zero_m  <= (others => '0');
            alpha    <= (others => '0');
            beta     <= (others => '0');
            zero     <= (others => '0');
            validReg <= (others => '0');
            alpha_o  <= (others => '0');
            beta_o   <= (others => '0');
            zero_o   <= (others => '0');
            data_valid_o <= '0';

        elsif rising_edge(sysclk) then

            -- Pipeline valid tracking (4-stage pipeline)
            validReg <= validReg(2 downto 0) & data_valid_i;

            -- Stage 0: register inputs (breaks long combinational path from upstream)
            a_reg <= a;
            b_reg <= b;
            c_reg <= c;

            -- Stage 1: compute sums from registered inputs
            b_half := shift_right(b_reg, 1);
            c_half := shift_right(c_reg, 1);
            alphaSum <= resize(a_reg, DATA_WIDTH+1) - resize(b_half, DATA_WIDTH+1) - resize(c_half, DATA_WIDTH+1);
            betaSum  <= resize(b_reg, DATA_WIDTH+1) - resize(c_reg, DATA_WIDTH+1);
            zeroSum  <= resize(a_reg, DATA_WIDTH+2) + resize(b_reg, DATA_WIDTH+2) + resize(c_reg, DATA_WIDTH+2);

            -- Stage 2: DSP48E1 M-register (behavioral multiplication)
            dsp_alpha_m <= COEFF_2_3     * alphaSum;
            dsp_beta_m  <= COEFF_1_SQRT3 * betaSum;
            dsp_zero_m  <= COEFF_1_3     * zeroSum;

            -- Stage 3: DSP48E1 P-register (passthrough with register)
            alpha <= dsp_alpha_m;
            beta  <= dsp_beta_m;
            zero  <= dsp_zero_m;
            
            -- Stage 4: extract output bits
            alpha_o <= alpha(FRAC_WIDTH + DATA_WIDTH - 1 downto FRAC_WIDTH);
            beta_o  <= beta(FRAC_WIDTH + DATA_WIDTH - 1 downto FRAC_WIDTH);
            zero_o  <= zero(FRAC_WIDTH + DATA_WIDTH - 1 downto FRAC_WIDTH);
            data_valid_o <= validReg(3);

        End if;
    End process;

End architecture;
