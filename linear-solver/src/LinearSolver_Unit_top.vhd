--! \file		LinearSolver_Unit_Top.vhd
--!
--! \brief		
--!
--! \author		Vinícius de Carvalho Monteiro Longo (longo.vinicius@gmail.com)
--! \date       15-07-2025
--!
--! \version    1.0
--!
--! \copyright	Copyright (c) 2025 - All Rights reserved.
--!
--! \note		Target devices : No specific target
--! \note		Tool versions  : No specific tool
--! \note		Dependencies   : No specific dependencies
--!
--! \ingroup
--! \warning	None
--!
--! \note		Revisions:

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Solver_pkg.all;

entity LinearSolver_Unit_Top is
    generic (
        CLK_FREQ                : integer := 160e6;
        BLINKY_PERIOD_US        : integer := 500e3;
        CICLES_TO_HIGH : integer   := 10000;
        CICLES_TO_LOW  : integer   := 10000;
        OUTPUT_INIT    : std_logic := '0'
    );
    port (
        SYSCLK_P                : in std_logic;
        SYSCLK_N                : in std_logic;

        GPIO_LED0               : out std_logic;
        GPIO_SW_C               : in std_logic
    );
end entity;

architecture arch of LinearSolver_Unit_Top is

    signal sysclk_100mhz        : std_logic;
    signal button_signal        : std_logic;
    signal reset_n              : std_logic := '0';
    signal reset_ctr            : unsigned(16 downto 0) := (others => '0');
    signal start_ctr            : unsigned(16 downto 0) := (others => '0');


    --------------------------------------------------------------------------
    -- Constants definition
    --------------------------------------------------------------------------
    constant N_SS_TB        : natural := 5;
    constant N_IN_TB        : natural := 2;
    constant CLK_PERIOD     : time    := 10 ns; -- Clock de 100 MHz
    constant RESET_TRHD     : integer := 100;
    constant START_TRHD     : integer := 50;

    --------------------------------------------------------------------------
    -- Factors
    --------------------------------------------------------------------------
    constant FACTORS1       : vector_fp_t(0 to N_SS_TB - 1) := (
        x"000100000000", x"000100000000", x"000100000000", x"000100000000", x"000100000000"
    );

    constant FACTORS2       : vector_fp_t(0 to N_IN_TB - 1) := (
        x"000200000000", x"000200000000"
    );

    --------------------------------------------------------------------------
    -- UUT ports
    --------------------------------------------------------------------------
    signal Avec_i        : vector_fp_t(0 to N_SS_TB - 1) := FACTORS1;
    signal Xvec_i        : vector_fp_t(0 to N_SS_TB - 1) := FACTORS1;
    signal Bvec_i        : vector_fp_t(0 to N_IN_TB - 1) := FACTORS2;
    signal Uvec_i        : vector_fp_t(0 to N_IN_TB - 1) := FACTORS2;
    signal stateResult_o : fixed_point_data_t;
    signal busy_o        : std_logic;

begin

    --------------------------------------------------------------------------
    -- PLL Instantiantion
    --------------------------------------------------------------------------    
    clock_gen_inst : entity work.clk_wiz_0
        port map(
            clk_in1_p => SYSCLK_P,
            clk_in1_n => SYSCLK_N,
            clk_out1   => sysclk_100mhz
        );  

    --------------------------------------------------------------------------
    -- Process to generate reset signal
    --------------------------------------------------------------------------   
    process (sysclk_100mhz)
    begin
        if rising_edge(sysclk_100mhz) then
            if reset_ctr < RESET_TRHD then
                reset_ctr <= reset_ctr + 1;
                reset_n   <= '0';
            else
                reset_n   <= '1';
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- Process to generate start signal
    --------------------------------------------------------------------------    
    process (sysclk_100mhz)
    begin
        if rising_edge(sysclk_100mhz) then
            if reset_n = '1' then 
                if start_ctr < START_TRHD then
                    start_ctr     <= start_ctr + 1;
                    button_signal <= '0';
                else
                    start_ctr     <= (others => '0'); 
                    button_signal <= '1';
                end if;
            else
                start_ctr     <= (others => '0');
                button_signal <= '0';
            end if;
        end if;
    end process;


    --------------------------------------------------------------------------
    -- Blinky Led Instantiantion
    --------------------------------------------------------------------------
    blinky_inst : entity work.blinky(rtl)
        generic map(CLK_FREQ, BLINKY_PERIOD_US)
        port map(reset_n, sysclk_100mhz,'1',GPIO_LED0);


    --------------------------------------------------------------------------
    -- UUT Instantiantion
    --------------------------------------------------------------------------
    uut: Entity work.LinearSolver_Unit
        generic map (
            N_SS => N_SS_TB,
            N_IN => N_IN_TB
        )
        port map (
            sysclk        => sysclk_100mhz,
            start_i       => button_signal,
            Avec_i        => Avec_i,
            Xvec_i        => Xvec_i,
            Bvec_i        => Bvec_i,
            Uvec_i        => Uvec_i,
            stateResult_o => stateResult_o,
            busy_o        => busy_o
    );

    --------------------------------------------------------------------------
    -- ChipScope Instantiation
    --------------------------------------------------------------------------
    chiscope_inst : entity work.ila_0
        port map(
            clk         => sysclk_100mhz,
            probe0      => button_signal,
            probe1      => std_logic_vector(stateResult_o),
            probe2      => busy_o
        );

    -- --------------------------------------------------------------------------
    -- -- Button Interface Instantiantion
    -- --------------------------------------------------------------------------
    -- debouncer_inst : entity work.debouncer
    --     generic map(
    --         CICLES_TO_HIGH => CICLES_TO_HIGH,
    --         CICLES_TO_LOW  => CICLES_TO_LOW,
    --         OUTPUT_INIT    => OUTPUT_INIT 
    --     )
    --     port map(
    --         clk      => sysclk_100mhz,
    --         rst_n    => reset_n,
    --         input_i  => GPIO_SW_C,
    --         output_i => button_signal
    --     );

end arch ; -- arch