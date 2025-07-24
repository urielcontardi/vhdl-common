--! \file		PWMToVoltage.vhd
--!
--! \brief		
--!
--! \author		Vinícius de Carvalho Monteiro Longo (longo@weg.net)
--! \date       23-07-2025
--!
--! \version    1.0
--!
--! \copyright	Copyright (c) 2024 WEG - All Rights reserved.
--!
--! \note		Target devices : No specific target
--! \note		Tool versions  : No specific tool
--! \note		Dependencies   : No specific dependencies
--!
--! \ingroup	None
--! \warning	None
--!
--! \note		Revisions:
--!				- 1.0	23-07-2025	<longo@weg.net>
--!				First revision.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity PWMToVoltage is
    generic (
        VDC_VOLTAGE       : integer := 400;
        OUTPUT_BIT_WIDTH  : integer := 48;
        FP_FRACTION_BITS  : integer := 32
    );
    port (
        sysclk     : in std_logic; 
        pwm_signal : in std_logic;
        v_in       : out std_logic_vector(OUTPUT_BIT_WIDTH-1 downto 0)
    );
end PWMToVoltage;

architecture Behavioral of PWMToVoltage is
    constant VDC       : SIGNED(OUTPUT_BIT_WIDTH-1 downto 0) := to_signed(VDC_VOLTAGE, OUTPUT_BIT_WIDTH);
    constant VDC_HIGH  : SIGNED(OUTPUT_BIT_WIDTH-1 downto 0) := shift_left(VDC, FP_FRACTION_BITS); 
    constant VDC_LOW   : SIGNED(OUTPUT_BIT_WIDTH-1 downto 0) := -shift_left(VDC, FP_FRACTION_BITS);

    signal v_in_internal : SIGNED(OUTPUT_BIT_WIDTH-1 downto 0);
begin

    process(sysclk)
    begin
        if rising_edge(sysclk) then 
            if pwm_signal = '1' then
                v_in_internal <= VDC_HIGH;
            else
                v_in_internal <= VDC_LOW;
            end if;
        end if;
    end process;

    -- Conversão para STD_LOGIC_VECTOR na saída
    v_in <= std_logic_vector(v_in_internal);

end Behavioral;
