--! \file		fifo.vhd
--!
--! \brief		
--!
--! \author		Uriel Abe Contardi (urielcontardi@hotmail.com)
--! \date       08-02-2026
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
--!				- 1.0	08-02-2026	<urielcontardi@hotmail.com>
--!				First revision.
--------------------------------------------------------------------------
-- Standard libraries
--------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--------------------------------------------------------------------------
-- Entity declaration
--------------------------------------------------------------------------
Entity Fifo is
    Generic (
        G_DATA_WIDTH     : integer := 16;   --! Width of data bus
        G_ADDR_BITS      : integer := 7;    --! Address bits (depth = 2^G_ADDR_BITS)
        G_REGISTERED_OUT : boolean := true  --! true: registered output (1 cycle latency)
                                            --! false: combinatorial output (0 latency)
    );
    Port ( 
        clk_i           : in  std_logic;
        rst_n_i         : in  std_logic;
        
        -- Write Port
        wr_en_i         : in  std_logic;
        wr_data_i       : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);
        
        -- Read Port  
        rd_en_i         : in  std_logic;
        rd_data_o       : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);
        
        -- Status
        is_empty_o      : out std_logic;
        almost_empty_o  : out std_logic;
        is_full_o       : out std_logic;
        fill_level_o    : out std_logic_vector(G_ADDR_BITS downto 0)  --! Needs extra bit for full count
    );
end entity;

--------------------------------------------------------------------------
-- Architecture
--------------------------------------------------------------------------
Architecture Behavioral of Fifo is

    -- Memory Configuration
    constant C_DEPTH     : integer := 2 ** G_ADDR_BITS;
    constant C_MAX_INDEX : integer := C_DEPTH - 1;

    -- Memory Array Type
    type t_memory_array is array (0 to C_MAX_INDEX) of 
        std_logic_vector(G_DATA_WIDTH - 1 downto 0);

    -- Internal Memory (not reset to allow BRAM inference)
    signal mem_array : t_memory_array;

    -- Pointer Registers
    signal wr_idx_reg : integer range 0 to C_MAX_INDEX := 0;
    signal rd_idx_reg : integer range 0 to C_MAX_INDEX := 0;

    -- Element Counter
    signal elem_count_reg : integer range 0 to C_DEPTH := 0;

    -- Status Flags (internal)
    signal empty_flag_reg       : std_logic := '1';
    signal almost_empty_flag_reg: std_logic := '1';
    signal full_flag_reg        : std_logic := '0';

    -- Output Data Register (initialized for BRAM inference)
    signal output_data_reg : std_logic_vector(rd_data_o'range) := (others => '0');

Begin

    ---------------------------------------------------------------------------
    -- Core Control Process
    -- Manages write/read pointers and status flags
    ---------------------------------------------------------------------------
    CoreControl_Proc : process(clk_i, rst_n_i)
        variable v_wr_idx     : integer range 0 to C_MAX_INDEX;
        variable v_rd_idx     : integer range 0 to C_MAX_INDEX;
        variable v_elem_count : integer range 0 to C_DEPTH;
    begin
        if rst_n_i = '0' then
            wr_idx_reg            <= 0;
            rd_idx_reg            <= 0;
            elem_count_reg        <= 0;
            empty_flag_reg        <= '1';
            almost_empty_flag_reg <= '1';
            full_flag_reg         <= '0';

        elsif rising_edge(clk_i) then
            -- Load current values into variables
            v_wr_idx     := wr_idx_reg;
            v_rd_idx     := rd_idx_reg;
            v_elem_count := elem_count_reg;

            -- Handle Read Request
            if (rd_en_i = '1') and (empty_flag_reg = '0') then
                v_elem_count := v_elem_count - 1;
                
                -- Circular increment of read index
                if v_rd_idx = C_MAX_INDEX then
                    v_rd_idx := 0;
                else
                    v_rd_idx := v_rd_idx + 1;
                end if;
            end if;

            -- Handle Write Request
            if (wr_en_i = '1') and (full_flag_reg = '0') then
                v_elem_count := v_elem_count + 1;
                mem_array(v_wr_idx) <= wr_data_i;
                
                -- Circular increment of write index
                if v_wr_idx = C_MAX_INDEX then
                    v_wr_idx := 0;
                else
                    v_wr_idx := v_wr_idx + 1;
                end if;
            end if;

            -- Update Status Flags
            if v_elem_count = 0 then
                empty_flag_reg <= '1';
            else
                empty_flag_reg <= '0';
            end if;

            if v_elem_count <= 1 then
                almost_empty_flag_reg <= '1';
            else
                almost_empty_flag_reg <= '0';
            end if;

            if v_elem_count = C_DEPTH then
                full_flag_reg <= '1';
            else
                full_flag_reg <= '0';
            end if;

            -- Update Registers
            wr_idx_reg     <= v_wr_idx;
            rd_idx_reg     <= v_rd_idx;
            elem_count_reg <= v_elem_count;

        end if;
    end process CoreControl_Proc;

    ---------------------------------------------------------------------------
    -- Read Data Path - Combinatorial Mode (Zero Latency)
    ---------------------------------------------------------------------------
    GenCombRead : if not G_REGISTERED_OUT generate
        output_data_reg <= mem_array(rd_idx_reg);
        
        -- Direct connection (no pipeline delay)
        is_empty_o     <= empty_flag_reg;
        almost_empty_o <= almost_empty_flag_reg;
    end generate GenCombRead;

    ---------------------------------------------------------------------------
    -- Read Data Path - Registered Mode (One Cycle Latency)
    ---------------------------------------------------------------------------
    GenRegRead : if G_REGISTERED_OUT generate
        
        RegReadData_Proc : process(clk_i)
        begin
            if rising_edge(clk_i) then
                output_data_reg <= mem_array(rd_idx_reg);
            end if;
        end process RegReadData_Proc;

    end generate GenRegRead;

    ---------------------------------------------------------------------------
    -- Status Signal Pipeline for Registered Mode
    -- Compensates for the 1-cycle read latency to prevent invalid reads
    ---------------------------------------------------------------------------
    GenStatusPipeline : if G_REGISTERED_OUT generate
        
        StatusDelay_Proc : process(clk_i, rst_n_i)
        begin
            if rst_n_i = '0' then
                is_empty_o     <= '1';
                almost_empty_o <= '1';
            elsif rising_edge(clk_i) then
                is_empty_o     <= empty_flag_reg;
                almost_empty_o <= almost_empty_flag_reg;
            end if;
        end process StatusDelay_Proc;

    end generate GenStatusPipeline;

    ---------------------------------------------------------------------------
    -- Output Assignments
    ---------------------------------------------------------------------------
    rd_data_o    <= output_data_reg;
    is_full_o    <= full_flag_reg;
    fill_level_o <= std_logic_vector(to_unsigned(elem_count_reg, G_ADDR_BITS + 1));

End architecture;
