--! \file		blinky.vhd
--!
--! \brief		
--!
--! \author		Uriel Abe Contardi (urielcontardi@hotmail.com)
--! \date       08-04-2022
--!
--! \version    1.0
--!
--! \copyright	Copyright (c) 2021 - All Rights reserved.
--!
--! \note		Target devices : No specific target
--! \note		Tool versions  : No specific tool
--! \note		Dependencies   : No specific dependencies
--!
--! \ingroup	None
--! \warning	None
--!
--! \note		Revisions:
--!				- 1.0	08-04-2022	<urielcontardi@hotmail.com>
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

--------------------------------------------------------------------------
-- Entity declaration
--------------------------------------------------------------------------
entity blinky is
    generic (
        CLK_FREQ         : integer := 160e6;
        BLINKY_PERIOD_US : integer := 1e6
    );
    port (
        reset_n  : in std_logic;
        sysclk   : in std_logic;
        enable_i : in std_logic;
        blinky_o : out std_logic
    );

end entity blinky;

--------------------------------------------------------------------------
-- Architecture 1
--------------------------------------------------------------------------
architecture rtl of blinky is

    --------------------------------------------------------------------------
    -- Signals
    --------------------------------------------------------------------------
    constant N_CYCLES_MICROSECOND : integer := CLK_FREQ/1e6;
    constant COUNTER_VALUE        : integer := N_CYCLES_MICROSECOND * BLINKY_PERIOD_US;
    signal counter                : integer range 0 to COUNTER_VALUE;
    signal blinky                 : std_logic;

begin

    Counter_seq : process (sysclk, reset_n)
    begin
        if reset_n = '0' then
            counter <= 0;
            blinky <= '0';

        elsif rising_edge(sysclk) then

            if enable_i = '1' then

                if counter = 0 then
                    counter <= COUNTER_VALUE;
                    blinky  <= not(blinky);
                else
                    counter <= counter - 1;

                end if;

            end if;

        end if;

    end process;

    blinky_o <= blinky;
end architecture ;