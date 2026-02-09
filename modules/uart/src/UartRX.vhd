--! \file       UartRX.vhd
--!
--! \brief      UART Receiver Module
--!             Receives serial data with configurable baud rate.
--!             Includes timeout detection and error checking.
--!
--! \author     Uriel Abe Contardi (urielcontardi@hotmail.com)
--! \date       08-02-2026
--!
--! \version    1.0
--!
--! \copyright  Copyright (c) 2026 - All Rights reserved.
--!
--! \note       Target devices : No specific target
--! \note       Tool versions  : No specific tool
--! \note       Dependencies   : No specific dependencies
--------------------------------------------------------------------------
-- Standard libraries
--------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--------------------------------------------------------------------------
-- Entity declaration
--------------------------------------------------------------------------
entity UartRX is
    generic (
        G_DATA_WIDTH : natural   := 8;      --! Data width (typically 8)
        G_START_BIT  : std_logic := '0';    --! Start bit polarity
        G_STOP_BIT   : std_logic := '1';    --! Stop bit polarity
        G_TOUT_BAUD  : natural   := 20      --! Timeout in baud periods (idle detection)
    );
    port (
        clk_i           : in  std_logic;    --! System clock
        rst_n_i         : in  std_logic;    --! Asynchronous reset (active low)
        
        -- UART Interface
        rx_i            : in  std_logic;    --! Serial RX input
        
        -- Configuration
        baudrate_i      : in  std_logic_vector(15 downto 0);  --! Baud rate divisor (clk/baud)
        
        -- Data Output
        data_o          : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);  --! Received data
        
        -- Status Flags
        rx_valid_o      : out std_logic;    --! New data available (pulse)
        rx_error_o      : out std_logic;    --! Frame error detected
        rx_timeout_o    : out std_logic;    --! Idle timeout (no activity)
        rx_busy_o       : out std_logic     --! Reception in progress
    );
end entity UartRX;

--------------------------------------------------------------------------
-- Architecture
--------------------------------------------------------------------------
architecture Behavioral of UartRX is

    ---------------------------------------------------------------------------
    -- State Machine Type
    ---------------------------------------------------------------------------
    type t_rx_state is (
        ST_IDLE,            --! Waiting for start bit
        ST_START_BIT,       --! Validating start bit
        ST_DATA_BITS,       --! Receiving data bits
        ST_STOP_BIT         --! Validating stop bit
    );

    ---------------------------------------------------------------------------
    -- Registers
    ---------------------------------------------------------------------------
    -- State machine
    signal state_reg        : t_rx_state := ST_IDLE;
    signal state_next       : t_rx_state;
    
    -- Data buffer
    signal data_reg         : std_logic_vector(G_DATA_WIDTH - 1 downto 0) := (others => '0');
    signal data_next        : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    
    -- Baud rate counter
    signal baud_cnt_reg     : unsigned(15 downto 0) := (others => '0');
    signal baud_cnt_next    : unsigned(15 downto 0);
    
    -- Bit counter
    signal bit_cnt_reg      : integer range 0 to G_DATA_WIDTH - 1 := 0;
    signal bit_cnt_next     : integer range 0 to G_DATA_WIDTH - 1;
    
    -- Configuration registers (sampled at start)
    signal baud_div_reg     : unsigned(15 downto 0) := (others => '0');
    signal baud_div_next    : unsigned(15 downto 0);
    signal half_baud_reg    : unsigned(15 downto 0) := (others => '0');
    signal half_baud_next   : unsigned(15 downto 0);
    
    -- Status flags
    signal rx_valid_reg     : std_logic := '0';
    signal rx_valid_next    : std_logic;
    signal rx_error_reg     : std_logic := '0';
    signal rx_error_next    : std_logic;
    
    -- Timeout counter (counts baud periods in idle)
    signal tout_cnt_reg     : integer range 0 to G_TOUT_BAUD := 0;
    signal tout_cnt_next    : integer range 0 to G_TOUT_BAUD;
    signal tout_baud_reg    : unsigned(15 downto 0) := (others => '0');
    signal tout_baud_next   : unsigned(15 downto 0);
    signal timeout_reg      : std_logic := '0';
    signal timeout_next     : std_logic;
    
    -- RX input synchronization and edge detection
    signal rx_sync1         : std_logic := '1';
    signal rx_sync2         : std_logic := '1';
    signal rx_sync3         : std_logic := '1';
    signal rx_falling       : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    data_o       <= data_reg;
    rx_valid_o   <= rx_valid_reg;
    rx_error_o   <= rx_error_reg;
    rx_timeout_o <= timeout_reg;
    rx_busy_o    <= '0' when state_reg = ST_IDLE else '1';

    ---------------------------------------------------------------------------
    -- RX Falling Edge Detection
    ---------------------------------------------------------------------------
    rx_falling <= rx_sync2 and (not rx_sync1);

    ---------------------------------------------------------------------------
    -- Sequential Process
    ---------------------------------------------------------------------------
    Seq_Proc : process(clk_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            -- State machine
            state_reg       <= ST_IDLE;
            -- Data
            data_reg        <= (others => '0');
            -- Counters
            baud_cnt_reg    <= (others => '0');
            bit_cnt_reg     <= 0;
            -- Configuration
            baud_div_reg    <= (others => '0');
            half_baud_reg   <= (others => '0');
            -- Status
            rx_valid_reg    <= '0';
            rx_error_reg    <= '0';
            -- Timeout
            tout_cnt_reg    <= 0;
            tout_baud_reg   <= (others => '0');
            timeout_reg     <= '0';
            -- Synchronizers (idle high)
            rx_sync1        <= '1';
            rx_sync2        <= '1';
            rx_sync3        <= '1';
            
        elsif rising_edge(clk_i) then
            -- State machine
            state_reg       <= state_next;
            -- Data
            data_reg        <= data_next;
            -- Counters
            baud_cnt_reg    <= baud_cnt_next;
            bit_cnt_reg     <= bit_cnt_next;
            -- Configuration
            baud_div_reg    <= baud_div_next;
            half_baud_reg   <= half_baud_next;
            -- Status
            rx_valid_reg    <= rx_valid_next;
            rx_error_reg    <= rx_error_next;
            -- Timeout
            tout_cnt_reg    <= tout_cnt_next;
            tout_baud_reg   <= tout_baud_next;
            timeout_reg     <= timeout_next;
            -- Input synchronization (2-stage + edge detect)
            rx_sync1        <= rx_i;
            rx_sync2        <= rx_sync1;
            rx_sync3        <= rx_sync2;
        end if;
    end process Seq_Proc;

    ---------------------------------------------------------------------------
    -- Combinatorial Process - State Machine
    ---------------------------------------------------------------------------
    Comb_Proc : process(state_reg, data_reg, baud_cnt_reg, bit_cnt_reg,
                        baud_div_reg, half_baud_reg, rx_valid_reg, rx_error_reg,
                        tout_cnt_reg, tout_baud_reg, timeout_reg,
                        rx_falling, rx_sync2, baudrate_i)
    begin
        -- Default: maintain current values
        state_next      <= state_reg;
        data_next       <= data_reg;
        baud_cnt_next   <= baud_cnt_reg;
        bit_cnt_next    <= bit_cnt_reg;
        baud_div_next   <= baud_div_reg;
        half_baud_next  <= half_baud_reg;
        rx_valid_next   <= '0';  -- Pulse, default low
        rx_error_next   <= '0';  -- Pulse, default low
        tout_cnt_next   <= tout_cnt_reg;
        tout_baud_next  <= tout_baud_reg;
        timeout_next    <= timeout_reg;

        -- State machine
        case state_reg is
            
            ---------------------------------------------------------------
            -- IDLE: Wait for falling edge (start bit)
            ---------------------------------------------------------------
            when ST_IDLE =>
                -- Timeout counter (counts baud periods while idle)
                if baud_div_reg /= 0 then
                    if tout_baud_reg >= baud_div_reg - 1 then
                        tout_baud_next <= (others => '0');
                        if tout_cnt_reg < G_TOUT_BAUD then
                            tout_cnt_next <= tout_cnt_reg + 1;
                        else
                            timeout_next <= '1';
                        end if;
                    else
                        tout_baud_next <= tout_baud_reg + 1;
                    end if;
                end if;

                -- Falling edge detected - start bit beginning
                if rx_falling = '1' then
                    state_next      <= ST_START_BIT;
                    baud_cnt_next   <= (others => '0');
                    bit_cnt_next    <= 0;
                    data_next       <= (others => '0');
                    -- Sample configuration
                    baud_div_next   <= unsigned(baudrate_i);
                    half_baud_next  <= unsigned('0' & baudrate_i(15 downto 1));
                    -- Clear timeout
                    tout_cnt_next   <= 0;
                    tout_baud_next  <= (others => '0');
                    timeout_next    <= '0';
                end if;

            ---------------------------------------------------------------
            -- START BIT: Sample at middle of bit
            ---------------------------------------------------------------
            when ST_START_BIT =>
                if baud_cnt_reg >= half_baud_reg - 1 then
                    -- Sample at middle of start bit
                    if rx_sync2 = G_START_BIT then
                        -- Valid start bit
                        state_next    <= ST_DATA_BITS;
                        baud_cnt_next <= (others => '0');
                    else
                        -- Invalid start bit (noise)
                        state_next    <= ST_IDLE;
                        rx_error_next <= '1';
                    end if;
                else
                    baud_cnt_next <= baud_cnt_reg + 1;
                end if;

            ---------------------------------------------------------------
            -- DATA BITS: Sample at middle of each bit
            ---------------------------------------------------------------
            when ST_DATA_BITS =>
                if baud_cnt_reg >= baud_div_reg - 1 then
                    -- Sample data bit (LSB first)
                    data_next(bit_cnt_reg) <= rx_sync2;
                    baud_cnt_next <= (others => '0');
                    
                    if bit_cnt_reg = G_DATA_WIDTH - 1 then
                        -- All bits received
                        state_next <= ST_STOP_BIT;
                    else
                        bit_cnt_next <= bit_cnt_reg + 1;
                    end if;
                else
                    baud_cnt_next <= baud_cnt_reg + 1;
                end if;

            ---------------------------------------------------------------
            -- STOP BIT: Validate and output data
            ---------------------------------------------------------------
            when ST_STOP_BIT =>
                if baud_cnt_reg >= baud_div_reg - 1 then
                    if rx_sync2 = G_STOP_BIT then
                        -- Valid frame
                        rx_valid_next <= '1';
                    else
                        -- Frame error
                        rx_error_next <= '1';
                    end if;
                    state_next <= ST_IDLE;
                else
                    baud_cnt_next <= baud_cnt_reg + 1;
                end if;

        end case;
    end process Comb_Proc;

end architecture Behavioral;
