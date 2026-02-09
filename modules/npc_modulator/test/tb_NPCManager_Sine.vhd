--------------------------------------------------------------------------
--! \file       tb_NPCManager_Sine.vhd
--!
--! \brief      Testbench for NPCManager with sinusoidal three-phase references.
--!             Generates waveforms suitable for viewing PWM modulation.
--!
--! \author     Uriel Abe Contardi (urielcontardi@hotmail.com)
--! \date       01-02-2026
--!
--! \details    This testbench generates balanced three-phase sinusoidal
--!             references (120° phase shift) and runs the NPCManager to
--!             produce PWM gate signals. Use GTKWave to visualize.
--------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

--------------------------------------------------------------------------
-- Entity
--------------------------------------------------------------------------
Entity tb_NPCManager_Sine is
End entity;

--------------------------------------------------------------------------
-- Architecture
--------------------------------------------------------------------------
Architecture sim of tb_NPCManager_Sine is

    --------------------------------------------------------------------------
    -- Types for visualization
    --------------------------------------------------------------------------
    -- NPC output level (human-readable in waveform)
    type npc_level_t is (LVL_POS, LVL_ZERO, LVL_NEG, LVL_DEAD_P, LVL_DEAD_N, LVL_OFF);

    --------------------------------------------------------------------------
    -- Constants
    --------------------------------------------------------------------------
    constant CLK_PERIOD     : time := 10 ns;      -- 100 MHz
    constant CLK_FREQ       : natural := 100_000_000;
    constant PWM_FREQ       : natural := 10_000;  -- 10 kHz PWM
    constant DATA_WIDTH     : natural := 16;
    constant MIN_PULSE      : integer := 50;
    constant DEAD_TIME      : integer := 25;
    constant WAIT_STATE_CNT : integer := 1000;

    -- Simulation parameters
    constant FUND_FREQ      : real := 50.0;       -- 50 Hz fundamental
    constant MODULATION_IDX : real := 0.85;       -- Modulation index (0 to 1)
    constant SIM_CYCLES     : integer := 3;       -- Number of fundamental cycles to simulate
    constant SIM_TIME       : time := (1.0/FUND_FREQ) * real(SIM_CYCLES) * 1 sec;

    -- Carrier parameters (must match NPCModulator)
    constant CARRIER_PERIOD : natural := CLK_FREQ / PWM_FREQ;  -- 10000 cycles
    constant CARRIER_MAX    : natural := CARRIER_PERIOD / 2;   -- 5000

    --------------------------------------------------------------------------
    -- Signals
    --------------------------------------------------------------------------
    signal sysclk       : std_logic := '0';
    signal reset_n      : std_logic := '0';

    -- Control
    signal pwm_enb      : std_logic := '0';
    signal clear        : std_logic := '0';

    -- References (signed)
    signal va_ref       : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal vb_ref       : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal vc_ref       : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');

    -- Reference as real (for debugging in waveform viewer)
    signal va_ref_real  : real := 0.0;
    signal vb_ref_real  : real := 0.0;
    signal vc_ref_real  : real := 0.0;

    -- Outputs
    signal carrier_tick : std_logic;
    signal sample_tick  : std_logic;
    signal pwm_a        : std_logic_vector(3 downto 0);
    signal pwm_b        : std_logic_vector(3 downto 0);
    signal pwm_c        : std_logic_vector(3 downto 0);
    signal pwm_on       : std_logic;
    signal fault_out    : std_logic;
    signal fs_fault     : std_logic;
    signal minw_fault   : std_logic;

    -- Individual gate signals (for easier viewing)
    signal s1_a, s2_a, s3_a, s4_a : std_logic;
    signal s1_b, s2_b, s3_b, s4_b : std_logic;
    signal s1_c, s2_c, s3_c, s4_c : std_logic;

    -- NPC output level (enum for clear visualization)
    signal level_a      : npc_level_t := LVL_OFF;
    signal level_b      : npc_level_t := LVL_OFF;
    signal level_c      : npc_level_t := LVL_OFF;

    -- Reconstructed output voltage (for visualization) - phase to neutral
    signal van          : real := 0.0;  -- Phase A to neutral
    signal vbn          : real := 0.0;  -- Phase B to neutral
    signal vcn          : real := 0.0;  -- Phase C to neutral

    -- Line-to-line voltages
    signal vab          : real := 0.0;  -- Phase A to B
    signal vbc          : real := 0.0;  -- Phase B to C
    signal vca          : real := 0.0;  -- Phase C to A

    -- Filtered output (simple moving average for fundamental visualization)
    signal van_filt     : real := 0.0;
    signal vbn_filt     : real := 0.0;
    signal vcn_filt     : real := 0.0;

    -- Legacy names for compatibility
    signal vout_a       : real := 0.0;
    signal vout_b       : real := 0.0;
    signal vout_c       : real := 0.0;

    -- Simulation control
    signal sim_done     : boolean := false;
    signal sim_time_s   : real := 0.0;

Begin

    --------------------------------------------------------------------------
    -- Clock generation
    --------------------------------------------------------------------------
    sysclk <= not sysclk after CLK_PERIOD/2 when not sim_done else '0';

    --------------------------------------------------------------------------
    -- Track simulation time in seconds (for sine generation)
    --------------------------------------------------------------------------
    process
    begin
        while not sim_done loop
            wait until rising_edge(sysclk);
            sim_time_s <= sim_time_s + (real(CLK_PERIOD / 1 ns) * 1.0e-9);
        end loop;
        wait;
    end process;

    --------------------------------------------------------------------------
    -- Three-phase sinusoidal reference generation
    --------------------------------------------------------------------------
    process(sysclk)
        variable t        : real;
        variable omega    : real;
        variable max_val  : real;
        variable ref_a    : real;
        variable ref_b    : real;
        variable ref_c    : real;
    begin
        if rising_edge(sysclk) then
            t := sim_time_s;
            omega := 2.0 * MATH_PI * FUND_FREQ;
            
            -- Reference amplitude = CARRIER_MAX for 100% modulation
            -- Modulation index scales this amplitude
            max_val := real(CARRIER_MAX);

            -- Three-phase balanced (120° phase shift)
            ref_a := MODULATION_IDX * sin(omega * t);
            ref_b := MODULATION_IDX * sin(omega * t - 2.0 * MATH_PI / 3.0);
            ref_c := MODULATION_IDX * sin(omega * t + 2.0 * MATH_PI / 3.0);

            -- Store for debug (normalized -1 to +1)
            va_ref_real <= ref_a;
            vb_ref_real <= ref_b;
            vc_ref_real <= ref_c;

            -- Convert to fixed-point (range ±CARRIER_MAX)
            va_ref <= std_logic_vector(to_signed(integer(ref_a * max_val), DATA_WIDTH));
            vb_ref <= std_logic_vector(to_signed(integer(ref_b * max_val), DATA_WIDTH));
            vc_ref <= std_logic_vector(to_signed(integer(ref_c * max_val), DATA_WIDTH));
        end if;
    end process;

    --------------------------------------------------------------------------
    -- DUT instantiation
    --------------------------------------------------------------------------
    DUT: entity work.NPCManager
    generic map (
        CLK_FREQ        => CLK_FREQ,
        PWM_FREQ        => PWM_FREQ,
        DATA_WIDTH      => DATA_WIDTH,
        LOAD_BOTH_EDGES => false,
        OUTPUT_REG      => true,
        MIN_PULSE_WIDTH => MIN_PULSE,
        DEAD_TIME       => DEAD_TIME,
        WAIT_STATE_CNT  => WAIT_STATE_CNT,
        INVERTED_PWM    => false
    )
    port map (
        sysclk         => sysclk,
        reset_n        => reset_n,
        pwm_enb_i      => pwm_enb,
        clear_i        => clear,
        va_ref_i       => va_ref,
        vb_ref_i       => vb_ref,
        vc_ref_i       => vc_ref,
        carrier_tick_o => carrier_tick,
        sample_tick_o  => sample_tick,
        pwm_a_o        => pwm_a,
        pwm_b_o        => pwm_b,
        pwm_c_o        => pwm_c,
        pwm_on_o       => pwm_on,
        fault_o        => fault_out,
        fs_fault_o     => fs_fault,
        minw_fault_o   => minw_fault
    );

    --------------------------------------------------------------------------
    -- Extract individual gate signals (easier to view in waveform)
    --------------------------------------------------------------------------
    -- Phase A: pwm_a = S4 S3 S2 S1
    s1_a <= pwm_a(0);
    s2_a <= pwm_a(1);
    s3_a <= pwm_a(2);
    s4_a <= pwm_a(3);

    -- Phase B
    s1_b <= pwm_b(0);
    s2_b <= pwm_b(1);
    s3_b <= pwm_b(2);
    s4_b <= pwm_b(3);

    -- Phase C
    s1_c <= pwm_c(0);
    s2_c <= pwm_c(1);
    s3_c <= pwm_c(2);
    s4_c <= pwm_c(3);

    --------------------------------------------------------------------------
    -- Reconstruct output voltage and NPC levels (for visualization)
    -- 
    -- NPC 3-level output:
    --   +Vdc/2 (POS)     when S1=ON, S2=ON  → pwm = "0011"
    --   0 (NEUTRAL)      when S2=ON, S3=ON  → pwm = "0110"
    --   -Vdc/2 (NEG)     when S3=ON, S4=ON  → pwm = "1100"
    --
    -- Dead-time states:
    --   DEAD_P (S2 only) → pwm = "0010" (transition POS ↔ ZERO)
    --   DEAD_N (S3 only) → pwm = "0100" (transition NEG ↔ ZERO)
    --------------------------------------------------------------------------
    
    -- Function to decode PWM vector to NPC level
    decode_levels: process(pwm_a, pwm_b, pwm_c)
    begin
        -- Phase A level
        case pwm_a is
            when "0011" => level_a <= LVL_POS;
            when "0110" => level_a <= LVL_ZERO;
            when "1100" => level_a <= LVL_NEG;
            when "0010" => level_a <= LVL_DEAD_P;
            when "0100" => level_a <= LVL_DEAD_N;
            when others => level_a <= LVL_OFF;
        end case;

        -- Phase B level
        case pwm_b is
            when "0011" => level_b <= LVL_POS;
            when "0110" => level_b <= LVL_ZERO;
            when "1100" => level_b <= LVL_NEG;
            when "0010" => level_b <= LVL_DEAD_P;
            when "0100" => level_b <= LVL_DEAD_N;
            when others => level_b <= LVL_OFF;
        end case;

        -- Phase C level
        case pwm_c is
            when "0011" => level_c <= LVL_POS;
            when "0110" => level_c <= LVL_ZERO;
            when "1100" => level_c <= LVL_NEG;
            when "0010" => level_c <= LVL_DEAD_P;
            when "0100" => level_c <= LVL_DEAD_N;
            when others => level_c <= LVL_OFF;
        end case;
    end process;

    -- Reconstruct phase-to-neutral voltages (normalized to ±0.5)
    reconstruct_voltage: process(pwm_a, pwm_b, pwm_c)
    begin
        -- Phase A to neutral
        case pwm_a is
            when "0011" => van <= 0.5;    -- +Vdc/2
            when "0110" => van <= 0.0;    -- 0
            when "1100" => van <= -0.5;   -- -Vdc/2
            when "0010" => van <= 0.25;   -- Dead-time (assume mid-point)
            when "0100" => van <= -0.25;  -- Dead-time (assume mid-point)
            when others => van <= 0.0;    -- OFF
        end case;

        -- Phase B to neutral
        case pwm_b is
            when "0011" => vbn <= 0.5;
            when "0110" => vbn <= 0.0;
            when "1100" => vbn <= -0.5;
            when "0010" => vbn <= 0.25;
            when "0100" => vbn <= -0.25;
            when others => vbn <= 0.0;
        end case;

        -- Phase C to neutral
        case pwm_c is
            when "0011" => vcn <= 0.5;
            when "0110" => vcn <= 0.0;
            when "1100" => vcn <= -0.5;
            when "0010" => vcn <= 0.25;
            when "0100" => vcn <= -0.25;
            when others => vcn <= 0.0;
        end case;
    end process;

    -- Legacy compatibility
    vout_a <= van;
    vout_b <= vbn;
    vout_c <= vcn;

    -- Line-to-line voltages (5-level output: -1, -0.5, 0, +0.5, +1)
    vab <= van - vbn;
    vbc <= vbn - vcn;
    vca <= vcn - van;

    --------------------------------------------------------------------------
    -- Moving average filter for fundamental visualization
    -- Averages over one PWM period to extract the fundamental component
    -- This is much better than a simple IIR filter for PWM signals
    --------------------------------------------------------------------------
    filter_proc: process(sysclk)
        -- Buffer size = samples per PWM period = CLK_FREQ / PWM_FREQ = 10000
        -- Using smaller buffer for simulation efficiency (decimate by 100)
        constant DECIMATE    : integer := 100;
        constant BUFFER_SIZE : integer := CARRIER_PERIOD / DECIMATE;  -- 100 samples
        type real_array is array (0 to BUFFER_SIZE-1) of real;
        
        variable buf_a     : real_array := (others => 0.0);
        variable buf_b     : real_array := (others => 0.0);
        variable buf_c     : real_array := (others => 0.0);
        variable idx       : integer range 0 to BUFFER_SIZE-1 := 0;
        variable sum_a     : real := 0.0;
        variable sum_b     : real := 0.0;
        variable sum_c     : real := 0.0;
        variable dec_cnt   : integer range 0 to DECIMATE-1 := 0;
    begin
        if rising_edge(sysclk) then
            if reset_n = '0' then
                buf_a := (others => 0.0);
                buf_b := (others => 0.0);
                buf_c := (others => 0.0);
                idx := 0;
                sum_a := 0.0;
                sum_b := 0.0;
                sum_c := 0.0;
                dec_cnt := 0;
                van_filt <= 0.0;
                vbn_filt <= 0.0;
                vcn_filt <= 0.0;
            else
                -- Decimate to reduce buffer size
                if dec_cnt = DECIMATE-1 then
                    dec_cnt := 0;
                    
                    -- Subtract old value, add new value (running sum)
                    sum_a := sum_a - buf_a(idx) + van;
                    sum_b := sum_b - buf_b(idx) + vbn;
                    sum_c := sum_c - buf_c(idx) + vcn;
                    
                    -- Store new value
                    buf_a(idx) := van;
                    buf_b(idx) := vbn;
                    buf_c(idx) := vcn;
                    
                    -- Update index (circular buffer)
                    if idx = BUFFER_SIZE-1 then
                        idx := 0;
                    else
                        idx := idx + 1;
                    end if;
                    
                    -- Output average
                    van_filt <= sum_a / real(BUFFER_SIZE);
                    vbn_filt <= sum_b / real(BUFFER_SIZE);
                    vcn_filt <= sum_c / real(BUFFER_SIZE);
                else
                    dec_cnt := dec_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- Main test process
    --------------------------------------------------------------------------
    stim_proc: process
        -- Helper: wait N clock cycles
        procedure wait_clk(n : integer) is
        begin
            for i in 1 to n loop
                wait until rising_edge(sysclk);
            end loop;
        end procedure;

        -- Helper: wait for carrier tick
        procedure wait_carrier_tick is
        begin
            wait until rising_edge(sysclk) and carrier_tick = '1';
        end procedure;

    begin
        report "============================================================";
        report "   NPCManager Sinusoidal Testbench";
        report "============================================================";
        report "   Fundamental frequency: " & real'image(FUND_FREQ) & " Hz";
        report "   PWM frequency: " & integer'image(PWM_FREQ) & " Hz";
        report "   Modulation index: " & real'image(MODULATION_IDX);
        report "   Simulation time: " & integer'image(SIM_CYCLES) & " fundamental cycles";
        report "============================================================";

        -- Initial reset
        reset_n <= '0';
        pwm_enb <= '0';
        clear   <= '0';

        wait_clk(100);
        reset_n <= '1';
        wait_clk(100);

        report "Starting PWM...";

        -- Enable PWM (wait for carrier tick to sync)
        wait_carrier_tick;
        pwm_enb <= '1';

        -- Wait for startup (need transition to NEUTRAL)
        wait_carrier_tick;
        wait_carrier_tick;
        wait_clk(MIN_PULSE + DEAD_TIME + 50);

        report "PWM running. Generating sine waves...";

        -- Run for specified number of fundamental cycles
        wait for SIM_TIME;

        report "============================================================";
        report "   Simulation complete!";
        report "   Use GTKWave to view waveforms.";
        report "============================================================";
        report "";
        report "   === RECOMMENDED SIGNALS FOR VISUALIZATION ===";
        report "";
        report "   REFERENCE INPUTS (sinusoidal):";
        report "   - va_ref_real, vb_ref_real, vc_ref_real";
        report "";
        report "   NPC OUTPUT LEVELS (enum - easy to read):";
        report "   - level_a, level_b, level_c  (LVL_POS, LVL_ZERO, LVL_NEG, LVL_DEAD_P/N)";
        report "";
        report "   PHASE-TO-NEUTRAL VOLTAGES (3-level: -0.5, 0, +0.5):";
        report "   - van, vbn, vcn";
        report "";
        report "   LINE-TO-LINE VOLTAGES (5-level: -1, -0.5, 0, +0.5, +1):";
        report "   - vab, vbc, vca";
        report "";
        report "   FILTERED FUNDAMENTAL (low-pass filtered):";
        report "   - van_filt, vbn_filt, vcn_filt";
        report "";
        report "   GATE SIGNALS:";
        report "   - s1_a, s2_a, s3_a, s4_a (individual gates phase A)";
        report "   - pwm_a, pwm_b, pwm_c (4-bit patterns)";
        report "";
        report "   TIMING/STATUS:";
        report "   - carrier_tick, sample_tick";
        report "   - fault_o, fs_fault_o, minw_fault_o";
        report "============================================================";

        sim_done <= true;
        wait;
    end process;

End architecture;
