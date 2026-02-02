-- Testbench for NPCModulator
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_NPCModulator is
end entity;

architecture sim of tb_NPCModulator is
    -- Generics for DUT
    -- Note: CLK_FREQ/PWM_FREQ must be high enough for good PWM resolution
    -- Ex: 10MHz/20kHz = 500 (CARRIER_HALF=250, ~8 bits resolution)
    constant CLK_FREQ        : natural := 10_000_000;  -- 10 MHz (simulation/resolution tradeoff)
    constant PWM_FREQ        : natural := 20_000;      -- 20 kHz
    constant DATA_WIDTH      : natural := 32;
    constant LOAD_BOTH_EDGES : boolean := true;
    constant OUTPUT_REG      : boolean := true;        -- Output register for timing closure

    -- Clock period
    constant CLK_PERIOD      : time := 1 sec / CLK_FREQ;  -- 100 ns @ 10 MHz

    -- Clock and reset
    signal sysclk  : std_logic := '0';
    signal reset_n : std_logic := '0';

    -- References (fixed-point, signed, normalized to ±1)
    signal va_ref_i : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal vb_ref_i : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal vc_ref_i : std_logic_vector(DATA_WIDTH-1 downto 0);

    -- Outputs
    signal carrier_tick_o : std_logic;
    signal sample_tick_o  : std_logic;
    signal state_a_o      : std_logic_vector(1 downto 0);
    signal state_b_o      : std_logic_vector(1 downto 0);
    signal state_c_o      : std_logic_vector(1 downto 0);

    -- Previous states for logging
    signal prev_a : std_logic_vector(1 downto 0) := (others => '0');
    signal prev_b : std_logic_vector(1 downto 0) := (others => '0');
    signal prev_c : std_logic_vector(1 downto 0) := (others => '0');

    -- Debug: convert to real for visualization
    signal va_ref_real : real;
    signal vb_ref_real : real;
    signal vc_ref_real : real;

    -- Helpers
    function to_slv_real(x : real; width : natural) return std_logic_vector is
        variable fullscale_s : signed(width-1 downto 0);
        variable fullscale   : integer;
        variable xi          : integer;
        variable lim         : integer;
    begin
        -- fullscale = 0x7..7 (width bits, MSB=0, rest=1)
        fullscale_s := (others => '1');
        fullscale_s(fullscale_s'high) := '0';
        fullscale := to_integer(fullscale_s);

        xi := integer(round(x * real(fullscale)));
        if xi >  fullscale then xi :=  fullscale; end if;
        lim := -fullscale;
        if xi <  lim then xi :=  lim; end if;
        return std_logic_vector(to_signed(xi, width));
    end function;

begin
    -- Clock generation
    sysclk <= not sysclk after CLK_PERIOD / 2;

    -- Reset sequence
    process
    begin
        reset_n <= '0';
        wait for 100 ns;
        reset_n <= '1';
        wait;
    end process;

    -- Reference generation: three-phase sine at 50 Hz
    process(sysclk)
        constant Ts      : real := 1.0 / real(CLK_FREQ);
        constant f_ref   : real := 50.0;             -- 50 Hz fundamental
        constant two_pi  : real := 2.0 * math_pi;
        variable n       : integer := 0;
        variable t       : real;
        variable va, vb, vc : real;
    begin
        if rising_edge(sysclk) then
            n := n + 1;
            t := real(n) * Ts;
            va := sin(two_pi * f_ref * t);
            vb := sin(two_pi * f_ref * t - (2.0 * math_pi / 3.0));
            vc := sin(two_pi * f_ref * t + (2.0 * math_pi / 3.0));

            va_ref_i <= to_slv_real(va, DATA_WIDTH);
            vb_ref_i <= to_slv_real(vb, DATA_WIDTH);
            vc_ref_i <= to_slv_real(vc, DATA_WIDTH);
        end if;
    end process;

    -- UUT instantiation
    dut: entity work.NPCModulator
        generic map (
            CLK_FREQ        => CLK_FREQ,
            PWM_FREQ        => PWM_FREQ,
            DATA_WIDTH      => DATA_WIDTH,
            LOAD_BOTH_EDGES => LOAD_BOTH_EDGES,
            OUTPUT_REG      => OUTPUT_REG
        )
        port map (
            sysclk         => sysclk,
            reset_n        => reset_n,
            va_ref_i       => va_ref_i,
            vb_ref_i       => vb_ref_i,
            vc_ref_i       => vc_ref_i,
            carrier_tick_o => carrier_tick_o,
            sample_tick_o  => sample_tick_o,
            state_a_o      => state_a_o,
            state_b_o      => state_b_o,
            state_c_o      => state_c_o
        );

    -- Simple logging on state changes (no real conversion in critical loop)
    process(sysclk)
        variable cycle_count : integer := 0;
    begin
        if rising_edge(sysclk) then
            cycle_count := cycle_count + 1;
            
            -- Log every 1ms (10000 cycles @ 10MHz)
            if cycle_count mod 10000 = 0 then
                report "Tempo: " & integer'image(cycle_count / 10000) & " ms" severity note;
            end if;
            
            if sample_tick_o = '1' then
                report "sample_tick" severity note;
            end if;
            if carrier_tick_o = '1' then
                report "carrier_tick" severity note;
            end if;

            if state_a_o /= prev_a or state_b_o /= prev_b or state_c_o /= prev_c then
                report "state A=" & integer'image(to_integer(unsigned(state_a_o))) &
                       " B=" & integer'image(to_integer(unsigned(state_b_o))) &
                       " C=" & integer'image(to_integer(unsigned(state_c_o))) severity note;
                prev_a <= state_a_o;
                prev_b <= state_b_o;
                prev_c <= state_c_o;
            end if;
        end if;
    end process;

    -- Convert to real for visualization only (does not affect simulation)
    process
        variable fullscale : real;
    begin
        fullscale := real(2**(DATA_WIDTH-1) - 1);
        wait until rising_edge(sysclk);
        va_ref_real <= real(to_integer(signed(va_ref_i))) / fullscale;
        vb_ref_real <= real(to_integer(signed(vb_ref_i))) / fullscale;
        vc_ref_real <= real(to_integer(signed(vc_ref_i))) / fullscale;
    end process;

end architecture;
