--! \file       NPCModulator.vhd
--!
--! \brief      NPC 3-level modulator - Simple triangular carrier PWM.
--!
--! \author     Uriel Abe Contardi (urielcontardi@hotmail.com)
--! \date       08-02-2026
--!
--! \version    3.0
--!
--! \copyright  Copyright (c) 2025 - All Rights reserved.
--!
--! \details    Simple PWM modulator:
--!             - Triangular carrier: 0 to CARRIER_MAX
--!             - CARRIER_MAX = (CLK_FREQ / PWM_FREQ) / 2 = 2500 for 100MHz/20kHz
--!             - Direct comparison: |ref| > carrier → active state
--!             - User controls reference amplitude (no scaling inside)
--!
--!             Reference range: ±CARRIER_MAX for 100% modulation
--!             Example: CARRIER_MAX = 2500, ref = ±2125 for m=0.85
--!
--!             NPC States:
--!               "11" = POS  → +Vdc/2 (when ref > 0 and |ref| > carrier)
--!               "01" = ZERO → 0      (when |ref| <= carrier)
--!               "00" = NEG  → -Vdc/2 (when ref < 0 and |ref| > carrier)
--!
--! \note       Revisions:
--!             - 1.0  25-01-2026  First revision.
--!             - 2.0  01-02-2026  Pipeline optimization.
--!             - 3.0  08-02-2026  Simplified: no internal scaling.
--------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--------------------------------------------------------------------------
-- Entity declaration
--------------------------------------------------------------------------
Entity NPCModulator is
    Generic (
        CLK_FREQ         : natural := 100_000_000;  -- System clock (Hz)
        PWM_FREQ         : natural := 20_000;       -- PWM frequency (Hz)
        DATA_WIDTH       : natural := 16;           -- Reference bit width (signed)
        LOAD_BOTH_EDGES  : boolean := false;        -- Sample at valley+peak
        OUTPUT_REG       : boolean := true          -- Output register
    );
    Port (
        sysclk  : in std_logic;
        reset_n : in std_logic;

        --! Voltage references (signed, range ±CARRIER_MAX for 100% modulation)
        --! CARRIER_MAX = (CLK_FREQ / PWM_FREQ) / 2
        va_ref_i : in std_logic_vector(DATA_WIDTH-1 downto 0);
        vb_ref_i : in std_logic_vector(DATA_WIDTH-1 downto 0);
        vc_ref_i : in std_logic_vector(DATA_WIDTH-1 downto 0);

        --! Carrier synchronization tick (period start - valley)
        carrier_tick_o : out std_logic;
        --! Reference sampling tick
        sample_tick_o  : out std_logic;

        --! NPC state outputs:
        --!   "11" = POS  → +Vdc/2
        --!   "01" = ZERO → 0
        --!   "00" = NEG  → -Vdc/2
        state_a_o : out std_logic_vector(1 downto 0);
        state_b_o : out std_logic_vector(1 downto 0);
        state_c_o : out std_logic_vector(1 downto 0)
    );
End entity;

--------------------------------------------------------------------------
-- Architecture: Simplified RTL
--------------------------------------------------------------------------
Architecture rtl of NPCModulator is

    --------------------------------------------------------------------------
    -- Constants
    --------------------------------------------------------------------------
    constant CARRIER_PERIOD : natural := CLK_FREQ / PWM_FREQ;
    constant CARRIER_MAX    : natural := CARRIER_PERIOD / 2;
    
    function clog2(n : natural) return natural is
        variable result : natural := 0;
        variable value  : natural := n - 1;
    begin
        while value > 0 loop
            result := result + 1;
            value  := value / 2;
        end loop;
        return result;
    end function;
    
    constant CARRIER_BITS : natural := clog2(CARRIER_MAX + 1);

    --------------------------------------------------------------------------
    -- Signals
    --------------------------------------------------------------------------
    -- Carrier
    signal carrier      : unsigned(CARRIER_BITS-1 downto 0) := (others => '0');
    signal direction    : std_logic := '1';  -- '1' = up, '0' = down
    signal valley       : std_logic := '0';
    signal peak         : std_logic := '0';
    
    -- Latched references (sampled at valley/peak)
    signal va_ref       : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal vb_ref       : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal vc_ref       : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    
    -- Absolute values + sign (registered for timing)
    signal va_abs       : unsigned(CARRIER_BITS-1 downto 0) := (others => '0');
    signal vb_abs       : unsigned(CARRIER_BITS-1 downto 0) := (others => '0');
    signal vc_abs       : unsigned(CARRIER_BITS-1 downto 0) := (others => '0');
    signal va_sign      : std_logic := '0';
    signal vb_sign      : std_logic := '0';
    signal vc_sign      : std_logic := '0';
    
    -- Carrier pipeline (aligned with processed reference)
    signal carrier_d1   : unsigned(CARRIER_BITS-1 downto 0) := (others => '0');
    
    -- NPC states
    signal state_a      : std_logic_vector(1 downto 0) := "01";
    signal state_b      : std_logic_vector(1 downto 0) := "01";
    signal state_c      : std_logic_vector(1 downto 0) := "01";

    --------------------------------------------------------------------------
    -- Function: Saturate reference to carrier range
    -- If |ref| > CARRIER_MAX, saturate to CARRIER_MAX
    --------------------------------------------------------------------------
    function saturate_to_carrier(
        ref : signed(DATA_WIDTH-1 downto 0)
    ) return unsigned is
        variable ref_abs : signed(DATA_WIDTH-1 downto 0);
    begin
        -- Absolute value
        if ref < 0 then
            ref_abs := -ref;
        else
            ref_abs := ref;
        end if;
        
        -- Saturate to CARRIER_MAX
        if ref_abs > to_signed(CARRIER_MAX, DATA_WIDTH) then
            return to_unsigned(CARRIER_MAX, CARRIER_BITS);
        else
            return unsigned(ref_abs(CARRIER_BITS-1 downto 0));
        end if;
    end function;

    --------------------------------------------------------------------------
    -- Function: NPC state from magnitude and carrier
    --------------------------------------------------------------------------
    function get_npc_state(
        ref_abs  : unsigned(CARRIER_BITS-1 downto 0);
        carr     : unsigned(CARRIER_BITS-1 downto 0);
        ref_sign : std_logic
    ) return std_logic_vector is
    begin
        -- Both operands have same width - clean comparison
        if ref_abs > carr then
            if ref_sign = '0' then
                return "11";  -- POS
            else
                return "00";  -- NEG
            end if;
        else
            return "01";      -- ZERO
        end if;
    end function;

Begin

    --------------------------------------------------------------------------
    -- Triangular carrier generator
    --------------------------------------------------------------------------
    carrier_gen: process(sysclk, reset_n)
    begin
        if reset_n = '0' then
            carrier   <= (others => '0');
            direction <= '1';
            valley    <= '0';
            peak      <= '0';
        elsif rising_edge(sysclk) then
            valley <= '0';
            peak   <= '0';
            
            if direction = '1' then
                -- Counting up
                if carrier >= to_unsigned(CARRIER_MAX - 1, CARRIER_BITS) then
                    direction <= '0';
                    peak <= '1';
                else
                    carrier <= carrier + 1;
                end if;
            else
                -- Counting down
                if carrier = 0 then
                    direction <= '1';
                    valley <= '1';
                else
                    carrier <= carrier - 1;
                end if;
            end if;
        end if;
    end process;

    -- Output ticks
    carrier_tick_o <= valley;
    sample_tick_o  <= valley or peak when LOAD_BOTH_EDGES else valley;

    --------------------------------------------------------------------------
    -- Reference sampling (at valley and optionally peak)
    --------------------------------------------------------------------------
    ref_sample: process(sysclk, reset_n)
    begin
        if reset_n = '0' then
            va_ref <= (others => '0');
            vb_ref <= (others => '0');
            vc_ref <= (others => '0');
        elsif rising_edge(sysclk) then
            if valley = '1' or (LOAD_BOTH_EDGES and peak = '1') then
                va_ref <= signed(va_ref_i);
                vb_ref <= signed(vb_ref_i);
                vc_ref <= signed(vc_ref_i);
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- Stage 1: Absolute value + sign extraction + carrier pipeline
    -- Registered for better timing and alignment
    --------------------------------------------------------------------------
    abs_stage: process(sysclk, reset_n)
    begin
        if reset_n = '0' then
            va_abs     <= (others => '0');
            vb_abs     <= (others => '0');
            vc_abs     <= (others => '0');
            va_sign    <= '0';
            vb_sign    <= '0';
            vc_sign    <= '0';
            carrier_d1 <= (others => '0');
        elsif rising_edge(sysclk) then
            -- Extract sign
            va_sign <= va_ref(DATA_WIDTH-1);
            vb_sign <= vb_ref(DATA_WIDTH-1);
            vc_sign <= vc_ref(DATA_WIDTH-1);
            
            -- Saturated absolute value (same width as carrier)
            va_abs <= saturate_to_carrier(va_ref);
            vb_abs <= saturate_to_carrier(vb_ref);
            vc_abs <= saturate_to_carrier(vc_ref);
            
            -- Pipeline carrier for alignment
            carrier_d1 <= carrier;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- Stage 2: NPC state generation (aligned comparison)
    --------------------------------------------------------------------------
    state_gen: process(sysclk, reset_n)
    begin
        if reset_n = '0' then
            state_a <= "01";
            state_b <= "01";
            state_c <= "01";
        elsif rising_edge(sysclk) then
            -- Both ref_abs and carrier_d1 have CARRIER_BITS width
            state_a <= get_npc_state(va_abs, carrier_d1, va_sign);
            state_b <= get_npc_state(vb_abs, carrier_d1, vb_sign);
            state_c <= get_npc_state(vc_abs, carrier_d1, vc_sign);
        end if;
    end process;

    --------------------------------------------------------------------------
    -- Output register (optional)
    --------------------------------------------------------------------------
    gen_output_reg: if OUTPUT_REG generate
        p_output_reg: process(sysclk, reset_n)
        begin
            if reset_n = '0' then
                state_a_o <= "01";
                state_b_o <= "01";
                state_c_o <= "01";
            elsif rising_edge(sysclk) then
                state_a_o <= state_a;
                state_b_o <= state_b;
                state_c_o <= state_c;
            end if;
        end process;
    end generate;
    
    gen_output_direct: if not OUTPUT_REG generate
        state_a_o <= state_a;
        state_b_o <= state_b;
        state_c_o <= state_c;
    end generate;

End architecture;
