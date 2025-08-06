--! \file		ClarkeTransform.vhd
--!
--! \brief      Implements the Clarke Transform for three-phase systems.
--!             Calculates the components:
--!                 - X_alpha = (2/3) × (Xa - 0.5×Xb - 0.5×Xc)
--!                 - X_beta  = (1/√3) × (Xb - Xc)
--!                 - X_zero  = (1/3) × (Xa + Xb + Xc)
--!             All operations are performed in fixed-point (two's complement).
--!            
--! \author		Uriel Abe Contardi (urielcontardi@hotmail.com)
--! \date       06-06-2025
--!
--! \version    1.0
--!
--! \note		Target devices : No specific target
--! \note		Tool versions  : No specific tool
--! \note		Dependencies   : No specific dependencies
--!
--! \ingroup	None
--! \warning	None
--!
--! \note		Revisions:
--!				- 1.0	06-06-2025	<urielcontardi@hotmail.com>
--!				First revision.
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
   
    -- Constantes para os coeficientes em ponto fixo
    -- Para FRAC_WIDTH = 12: 2^12 = 4096
    constant COEFF_2_3     : signed(DATA_WIDTH-1 downto 0) := to_signed(integer(2.0/3.0 * 2**FRAC_WIDTH), DATA_WIDTH);  -- 2/3
    constant COEFF_1_SQRT3 : signed(DATA_WIDTH-1 downto 0) := to_signed(integer(1.0/1.732050808 * 2**FRAC_WIDTH), DATA_WIDTH); -- 1/√3
    constant COEFF_1_3     : signed(DATA_WIDTH-1 downto 0) := to_signed(integer(1.0/3.0 * 2**FRAC_WIDTH), DATA_WIDTH);  -- 1/3

    -- Input Signals
    signal a : signed(DATA_WIDTH - 1 downto 0);
    signal b : signed(DATA_WIDTH - 1 downto 0);
    signal c : signed(DATA_WIDTH - 1 downto 0);

    -- Alpha Signals
    signal alphaSum     : signed(DATA_WIDTH downto 0);  -- Extra bit for overflow
    signal alpha        : signed(2*DATA_WIDTH-1 downto 0);
    
    -- Beta Signals
    signal betaSum      : signed(DATA_WIDTH downto 0);
    signal beta         : signed(2*DATA_WIDTH-1 downto 0);
    
    -- Zero Signals
    signal zeroSum      : signed(DATA_WIDTH+1 downto 0); -- 2x Extra bit for overflow
    signal zero         : signed(DATA_WIDTH*2-1 downto 0);
    
    -- Pipeline
    signal validReg     : std_logic_vector(1 downto 0) := (others => '0');
    
Begin

    --------------------------------------------------------------------------
    -- Internal Signals
    --------------------------------------------------------------------------
    a <= signed(a_in);
    b <= signed(b_in);
    c <= signed(c_in);

    --------------------------------------------------------------------------
    -- Process: Clarke Transform
    --------------------------------------------------------------------------
    Process(sysclk, reset_n)
        variable b_half, c_half     : signed(DATA_WIDTH-1 downto 0);
    Begin
        if reset_n = '1' then

            alphaSum <= (others => '0');
            betaSum  <= (others => '0');
            zeroSum  <= (others => '0');
            alpha    <= (others => '0');
            beta     <= (others => '0');
            zero     <= (others => '0');
            validReg <= (others => '0');
            
        elsif rising_edge(sysclk) then

            -- Pipeline control
            validReg <= validReg(0 downto 0) & data_valid_i; -- Shift valid signal

            -- Alpha Calculation: (2/3) * (a - 0.5*b - 0.5*c)
            b_half := shift_right(b, 1); -- Divide by 2
            c_half := shift_right(c, 1); -- Divide by 2
            alphaSum <= resize(a, DATA_WIDTH+1) - resize(b_half, DATA_WIDTH+1) - resize(c_half, DATA_WIDTH+1);
            alpha    <= resize(COEFF_2_3, 2*DATA_WIDTH) * resize(alphaSum, 2*DATA_WIDTH);
            
            -- Beta Calculation: (1/√3) * (b - c)
            betaSum <= resize(b, DATA_WIDTH+1) - resize(c, DATA_WIDTH+1);
            beta    <= resize(COEFF_1_SQRT3, 2*DATA_WIDTH) * resize(betaSum, 2*DATA_WIDTH);

            -- Zero Calculation: (1/3) * (a + b + c)
            zeroSum <= resize(a, DATA_WIDTH+2) + resize(b, DATA_WIDTH+2) + resize(c, DATA_WIDTH+2);
            zero    <= resize(COEFF_1_3, 2*DATA_WIDTH) * resize(zeroSum, 2*DATA_WIDTH);

            -- Assign outputs
            alpha_o      <= resize(alpha(2*DATA_WIDTH-1 downto DATA_WIDTH), DATA_WIDTH);
            beta_o       <= resize(beta(2*DATA_WIDTH-1 downto DATA_WIDTH), DATA_WIDTH);
            zero_o       <= resize(zero(2*DATA_WIDTH-1 downto DATA_WIDTH), DATA_WIDTH);
            data_valid_o <= validReg(1);

        End if;
    End process;

End architecture;
