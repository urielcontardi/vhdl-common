--! \file		EdgeDetector.vhd
--!
--! \brief		Edge Detector
--!
--! \author		Uriel Abe Contardi (urielcontardi@hotmail.com)
--! \date       08-08-2025
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
--!				- 1.0	08-08-2025	<urielcontardi@hotmail.com>
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
Entity EdgeDetector is
    Generic (
        BOTH_EDGES : std_logic := '0';  -- Set to '1' to detect both edges. Overrides EDGE.
        EDGE       : std_logic := '1'   -- Set to '0' for falling
    );
    Port (
        sysclk   : in std_logic;
        reset_n  : in std_logic;
        signal_i : in std_logic;
        tick_o   : out std_logic
    );
End entity;

--------------------------------------------------------------------------
-- Architecture
--------------------------------------------------------------------------
Architecture rtl of EdgeDetector is

    --------------------------------------------------------------------------
    -- Signal declarations
    --------------------------------------------------------------------------
    signal signal_d1       : std_logic;
    signal signal_d2       : std_logic;
    signal rising_edge_det : std_logic;
    signal falling_edge_det: std_logic;
    signal edge_detect     : std_logic;
    signal tick_reg        : std_logic;

Begin

    --------------------------------------------------------------------------
    -- Edge detection logic
    --------------------------------------------------------------------------
    process(sysclk, reset_n)
    begin
        if reset_n = '0' then
            signal_d1 <= '0';
            signal_d2 <= '0';
        elsif rising_edge(sysclk) then
            signal_d1 <= signal_i;
            signal_d2 <= signal_d1;
        end if;
    end process;

    -- Edge detection
    rising_edge_det  <= signal_d1 and not signal_d2;
    falling_edge_det <= not signal_d1 and signal_d2;

    -- Select which edge(s) to detect based on generics
    edge_detect <= (rising_edge_det or falling_edge_det) when BOTH_EDGES = '1' else
                   rising_edge_det when EDGE = '1' else
                   falling_edge_det;

    --------------------------------------------------------------------------
    -- Register edge_detect to produce a one-clock tick_o pulse
    --------------------------------------------------------------------------
    process(sysclk, reset_n)
    begin
        if reset_n = '0' then
            tick_reg <= '0';
        elsif rising_edge(sysclk) then
            tick_reg <= edge_detect;
        end if;
    end process;

    tick_o <= tick_reg;

End architecture;
