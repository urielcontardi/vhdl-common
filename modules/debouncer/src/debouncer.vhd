--! \file		debouncer.vhd
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
-- Entity declaration
--------------------------------------------------------------------------
entity debouncer is
	generic (
		CICLES_TO_HIGH : integer   := 128;
		CICLES_TO_LOW  : integer   := 128;
		OUTPUT_INIT    : std_logic := '0' -- Output Logic Level in the initialization, used just in arc_detect.vhd
	);
	port (
		clk      : in std_logic;
		rst_n    : in std_logic;
		input_i  : in std_logic;
		output_i : out std_logic
	);
end debouncer;

architecture rtl of debouncer is
	signal counter_h_reg, counter_h_next : integer range 0 to CICLES_TO_HIGH - 1;
	signal counter_l_reg, counter_l_next : integer range 0 to CICLES_TO_LOW - 1;

	signal input_last_reg, input_last_next : std_logic;

	signal output_reg, output_next : std_logic;
begin

	--------------------------------------------------------------------------
	-- State Machine Sequential Process
	--------------------------------------------------------------------------
	sequencial : process (clk, rst_n)
	begin
		if rst_n = '0' then
			counter_h_reg  <= 0;
			counter_l_reg  <= 0;
			input_last_reg <= OUTPUT_INIT;
			output_reg     <= OUTPUT_INIT;

		elsif rising_edge(clk) then
			counter_h_reg  <= counter_h_next;
			counter_l_reg  <= counter_l_next;
			input_last_reg <= input_last_next;
			output_reg     <= output_next;
		end if;
	end process;

	--------------------------------------------------------------------------
	-- State Machine Combinational Process
	--------------------------------------------------------------------------
	combinational : process (counter_h_reg, counter_l_reg, input_last_reg, output_reg, input_i)
	begin

		counter_h_next  <= counter_h_reg;
		counter_l_next  <= counter_l_reg;
		output_next     <= output_reg;
		input_last_next <= input_i;

		if input_i /= input_last_reg then
			counter_h_next <= 0;
			counter_l_next <= 0;

		elsif input_i = '0' then
			if counter_l_reg < CICLES_TO_LOW - 1 then
				counter_l_next <= counter_l_reg + 1;
			else
				output_next <= '0';
			end if;
		else -- input_i = '1'
			if counter_h_reg < CICLES_TO_HIGH - 1 then
				counter_h_next <= counter_h_reg + 1;
			else
				output_next <= '1';
			end if;
		end if;

	end process;

	output_i <= output_reg;

end ;