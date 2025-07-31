--! \file		tb_FixedPointConversion.vhd
--!
--! \brief		
--!
--! \author		Vinícius de Carvalho Monteiro Longo (longo.vinicius@gmail.com)
--! \date       23-07-2025
--!
--! \version    1.0
--!
--! \copyright	Copyright (c) 2024 - All Rights reserved.
--!
--! \note		Target devices : No specific target
--! \note		Tool versions  : No specific tool
--! \note		Dependencies   : No specific dependencies
--!
--! \ingroup	None
--! \warning	None
--!
--! \note		Revisions:
--!				- 1.0	23-07-2025	<longo.vinicius@gmail.com>
--!				First revision.
--------------------------------------------------------------------------
-- Default libraries
--------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.finish; 

use work.SolverPkg.all;

entity tb_FixedPointConversion is
end entity tb_FixedPointConversion;

architecture sim of tb_FixedPointConversion is

    signal res_0_5          : fixed_point_data_t;
    signal res_minus_0_5          : fixed_point_data_t;
    signal res_zero         : fixed_point_data_t;

begin

    test_process : process
    begin
        res_0_5 <= to_fp(0.5);
        wait for 100 ns; 
        res_minus_0_5 <= to_fp(-0.5);
        wait for 100 ns; 
        res_zero <= to_fp(0.0);
        wait for 100 ns;
        finish;
    end process test_process;

end architecture sim;