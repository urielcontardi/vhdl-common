--! \file       UartFull.vhd
--!
--! \brief      Complete UART Module with TX and RX FIFOs
--!             Integrates UartTX, UartRX, and FIFO modules for a complete
--!             buffered UART interface.
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
--! \note       Dependencies   : UartTX.vhd, UartRX.vhd, fifo.vhd
--------------------------------------------------------------------------
-- Standard libraries
--------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--------------------------------------------------------------------------
-- Entity declaration
--------------------------------------------------------------------------
entity UartFull is
    generic (
        -- Clock and Baud Configuration
        G_CLK_FREQ       : integer := 100_000_000;  --! System clock frequency (Hz)
        G_BAUD_RATE      : integer := 115200;       --! UART baud rate (bps)
        
        -- Data Configuration
        G_DATA_WIDTH     : integer := 8;            --! Data width (bits)
        
        -- FIFO Configuration
        G_TX_FIFO_DEPTH  : integer := 4;            --! TX FIFO depth (2^N entries)
        G_RX_FIFO_DEPTH  : integer := 4;            --! RX FIFO depth (2^N entries)
        G_FIFO_REG_OUT   : boolean := true;         --! Use registered FIFO output
        
        -- Timeout Configuration
        G_RX_TIMEOUT     : integer := 20            --! RX timeout (in baud periods)
    );
    port (
        clk_i            : in  std_logic;           --! System clock
        rst_n_i          : in  std_logic;           --! Asynchronous reset (active low)
        
        -- TX Interface (User side)
        tx_data_i        : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);  --! Data to transmit
        tx_wr_en_i       : in  std_logic;           --! Write to TX FIFO
        tx_enable_i      : in  std_logic := '1';    --! Enable TX (flow control)
        tx_full_o        : out std_logic;           --! TX FIFO full
        tx_empty_o       : out std_logic;           --! TX FIFO empty (all sent)
        tx_count_o       : out std_logic_vector(G_TX_FIFO_DEPTH downto 0);  --! TX FIFO fill level
        
        -- RX Interface (User side)
        rx_data_o        : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);  --! Received data
        rx_rd_en_i       : in  std_logic;           --! Read from RX FIFO
        rx_empty_o       : out std_logic;           --! RX FIFO empty
        rx_full_o        : out std_logic;           --! RX FIFO full
        rx_count_o       : out std_logic_vector(G_RX_FIFO_DEPTH downto 0);  --! RX FIFO fill level
        
        -- Status
        rx_error_o       : out std_logic;           --! Frame error detected
        rx_timeout_o     : out std_logic;           --! RX idle timeout
        tx_busy_o        : out std_logic;           --! TX is transmitting
        rx_busy_o        : out std_logic;           --! RX is receiving
        
        -- UART Physical Interface
        tx_o             : out std_logic;           --! UART TX line
        rx_i             : in  std_logic            --! UART RX line
    );
end entity UartFull;

--------------------------------------------------------------------------
-- Architecture
--------------------------------------------------------------------------
architecture Structural of UartFull is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    -- Baud rate divisor: clk_freq / baud_rate
    constant C_BAUD_DIV : integer := G_CLK_FREQ / G_BAUD_RATE;

    ---------------------------------------------------------------------------
    -- TX Signals
    ---------------------------------------------------------------------------
    signal tx_fifo_rd_data  : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal tx_fifo_empty    : std_logic;
    signal tx_fifo_rd_en    : std_logic;
    signal tx_start         : std_logic;
    signal tx_done          : std_logic;
    signal tx_busy          : std_logic;
    
    -- TX data latch: captures FIFO data before it changes
    signal tx_data_latch    : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    
    -- TX state machine
    type t_tx_state is (ST_TX_IDLE, ST_TX_WAIT_DATA, ST_TX_SEND, ST_TX_WAIT_DONE);
    signal tx_state_reg     : t_tx_state := ST_TX_IDLE;
    signal tx_state_next    : t_tx_state;

    ---------------------------------------------------------------------------
    -- RX Signals
    ---------------------------------------------------------------------------
    signal rx_data_from_uart : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal rx_valid          : std_logic;
    signal rx_error          : std_logic;
    signal rx_timeout        : std_logic;
    signal rx_uart_busy      : std_logic;

    ---------------------------------------------------------------------------
    -- Baudrate
    ---------------------------------------------------------------------------
    signal baudrate_cfg     : std_logic_vector(15 downto 0);

begin

    ---------------------------------------------------------------------------
    -- Baudrate Configuration
    ---------------------------------------------------------------------------
    baudrate_cfg <= std_logic_vector(to_unsigned(C_BAUD_DIV, 16));

    ---------------------------------------------------------------------------
    -- TX FIFO Instantiation
    ---------------------------------------------------------------------------
    TX_FIFO_Inst : entity work.Fifo
        generic map (
            G_DATA_WIDTH     => G_DATA_WIDTH,
            G_ADDR_BITS      => G_TX_FIFO_DEPTH,
            G_REGISTERED_OUT => G_FIFO_REG_OUT
        )
        port map (
            clk_i          => clk_i,
            rst_n_i        => rst_n_i,
            wr_en_i        => tx_wr_en_i,
            wr_data_i      => tx_data_i,
            rd_en_i        => tx_fifo_rd_en,
            rd_data_o      => tx_fifo_rd_data,
            is_empty_o     => tx_fifo_empty,
            almost_empty_o => open,
            is_full_o      => tx_full_o,
            fill_level_o   => tx_count_o
        );

    ---------------------------------------------------------------------------
    -- TX UART Instantiation
    ---------------------------------------------------------------------------
    TX_UART_Inst : entity work.UartTX
        generic map (
            DATA_WIDTH => G_DATA_WIDTH,
            START_BIT  => '0',
            STOP_BIT   => '1'
        )
        port map (
            sysclk     => clk_i,
            reset_n    => rst_n_i,
            start_i    => tx_start,
            baudrate_i => baudrate_cfg,
            data_i     => tx_data_latch,  -- Use latched data (captured before FIFO rd_idx advances)
            tx_o       => tx_o,
            tx_done_o  => tx_done
        );

    ---------------------------------------------------------------------------
    -- TX Controller State Machine
    -- Manages reading from FIFO and triggering TX
    ---------------------------------------------------------------------------
    TX_Ctrl_Seq : process(clk_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            tx_state_reg  <= ST_TX_IDLE;
            tx_data_latch <= (others => '0');
        elsif rising_edge(clk_i) then
            tx_state_reg <= tx_state_next;
            
            -- Latch FIFO data when reading (before rd_idx advances)
            if tx_fifo_rd_en = '1' then
                tx_data_latch <= tx_fifo_rd_data;
            end if;
        end if;
    end process TX_Ctrl_Seq;

    TX_Ctrl_Comb : process(tx_state_reg, tx_fifo_empty, tx_enable_i, tx_done)
    begin
        -- Defaults
        tx_state_next  <= tx_state_reg;
        tx_fifo_rd_en  <= '0';
        tx_start       <= '0';
        tx_busy        <= '0';

        case tx_state_reg is
            when ST_TX_IDLE =>
                -- Wait for data in FIFO and TX enabled
                if tx_fifo_empty = '0' and tx_enable_i = '1' then
                    tx_fifo_rd_en <= '1';  -- Read from FIFO
                    tx_state_next <= ST_TX_WAIT_DATA;
                end if;

            when ST_TX_WAIT_DATA =>
                -- Wait for FIFO data to be available (registered output)
                tx_busy       <= '1';
                tx_state_next <= ST_TX_SEND;

            when ST_TX_SEND =>
                -- Start transmission
                tx_busy       <= '1';
                tx_start      <= '1';
                tx_state_next <= ST_TX_WAIT_DONE;

            when ST_TX_WAIT_DONE =>
                -- Wait for TX to complete
                tx_busy <= '1';
                if tx_done = '1' then
                    tx_state_next <= ST_TX_IDLE;
                end if;

        end case;
    end process TX_Ctrl_Comb;

    -- TX status outputs
    tx_empty_o <= tx_fifo_empty;
    tx_busy_o  <= tx_busy or (not tx_fifo_empty);

    ---------------------------------------------------------------------------
    -- RX UART Instantiation
    ---------------------------------------------------------------------------
    RX_UART_Inst : entity work.UartRX
        generic map (
            G_DATA_WIDTH => G_DATA_WIDTH,
            G_START_BIT  => '0',
            G_STOP_BIT   => '1',
            G_TOUT_BAUD  => G_RX_TIMEOUT
        )
        port map (
            clk_i        => clk_i,
            rst_n_i      => rst_n_i,
            rx_i         => rx_i,
            baudrate_i   => baudrate_cfg,
            data_o       => rx_data_from_uart,
            rx_valid_o   => rx_valid,
            rx_error_o   => rx_error,
            rx_timeout_o => rx_timeout,
            rx_busy_o    => rx_uart_busy
        );

    ---------------------------------------------------------------------------
    -- RX FIFO Instantiation
    ---------------------------------------------------------------------------
    RX_FIFO_Inst : entity work.Fifo
        generic map (
            G_DATA_WIDTH     => G_DATA_WIDTH,
            G_ADDR_BITS      => G_RX_FIFO_DEPTH,
            G_REGISTERED_OUT => G_FIFO_REG_OUT
        )
        port map (
            clk_i          => clk_i,
            rst_n_i        => rst_n_i,
            wr_en_i        => rx_valid,
            wr_data_i      => rx_data_from_uart,
            rd_en_i        => rx_rd_en_i,
            rd_data_o      => rx_data_o,
            is_empty_o     => rx_empty_o,
            almost_empty_o => open,
            is_full_o      => rx_full_o,
            fill_level_o   => rx_count_o
        );

    -- RX status outputs
    rx_error_o   <= rx_error;
    rx_timeout_o <= rx_timeout;
    rx_busy_o    <= rx_uart_busy;

end architecture Structural;
