--! \file		uart_tx.vhd
--!
--! \brief		
--!
--! \author		Uriel Abe Contardi (urielcontardi@hotmail.com)
--! \date       18-05-2023
--!
--! \version    1.0
--!
--! \copyright	Copyright (c) 2022 - All Rights reserved.
--!
--! \note		Target devices : No specific target
--! \note		Tool versions  : No specific tool
--! \note		Dependencies   : No specific dependencies
--!
--! \ingroup	None
--! \warning	None
--!
--! \note		Revisions:
--!				- 1.0	18-05-2023	<urielcontardi@hotmail.com>
--!				First revision.
--------------------------------------------------------------------------
-- Default libraries
--------------------------------------------------------------------------
Library ieee;
Use ieee.std_logic_1164.all;
Use ieee.numeric_std.all;

--------------------------------------------------------------------------
-- Entity declaration
--------------------------------------------------------------------------
Entity Uart_TX is
	Generic (
		DATA_WIDTH		: natural 	:= 8; 
		START_BIT		: std_logic := '0';
		STOP_BIT		: std_logic := '1'
	);
	Port (
		sysclk		: in  std_logic;
		reset_n    	: in  std_logic;
		
		-- Start data transfer
		start_i		: in  std_logic;

        -- Baudrate Counter
        baudrate_i	: in std_logic_vector(15 downto 0);
		
		-- Data to be sent
		data_i		: in  std_logic_vector(DATA_WIDTH - 1 downto 0);
		
		-- TX signal
		tx_o		: out std_logic;
		
		-- Done flag
		tx_done_o	: out std_logic
	);
End Entity;

--------------------------------------------------------------------------
-- Architecture (system behavior)
--------------------------------------------------------------------------
Architecture behavior of Uart_TX is

	--// Data types
		-- State Machine
	type FSM_STATES is (IDLE_ST, SEND_DATA_ST, GET_DATA_ST, WAIT_ST);

	--// Signals
		-- State Machine
	signal state_next, state_reg					: FSM_STATES;

		-- Output
	signal tx_o_next, tx_o_reg						: std_logic;
	signal tx_done_next, tx_done_reg				: std_logic;

		-- Data register
	signal data_next, data_reg						: std_logic_vector(DATA_WIDTH + 1 downto 0);	-- Length DATA_WIDTH + 2 to include Start & Stop bit

        -- Baudrate register
    signal baudrate_reg, baudrate_next              : std_logic_vector(baudrate_i'range);

		-- Counters (baudrate and data width)
	signal ctr_baud_next, ctr_baud_reg				: unsigned(baudrate_i'range);
	signal ctr_data_bit_next, ctr_data_bit_reg		: integer range 0 to DATA_WIDTH + 1;

		-- Delay Valid Data from FIFO
	signal delay_fifo_next, delay_fifo_reg			: std_logic;

Begin

	--// Assign Outputs
	tx_o		<= tx_o_reg;
	tx_done_o	<= tx_done_reg;

	--// State Machine
	-- Sequential
	StateMachine_Seq: process(sysclk, reset_n)
	begin
		if rising_edge(sysclk) then
			if reset_n = '0' then
				state_reg			<= IDLE_ST;
				tx_o_reg			<= '1';
				data_reg			<= (others => '0');
				tx_done_reg			<= '0';
				ctr_baud_reg		<= (others => '0');
                baudrate_reg        <= (others => '0');
				ctr_data_bit_reg	<= 0;
				delay_fifo_reg		<= '0';
			else
				state_reg			<= state_next;
				tx_o_reg			<= tx_o_next;
				tx_done_reg			<= tx_done_next;
				data_reg			<= data_next;
				ctr_baud_reg		<= ctr_baud_next;
                baudrate_reg        <= baudrate_next;
				ctr_data_bit_reg	<= ctr_data_bit_next;
				delay_fifo_reg		<= delay_fifo_next;
			end if;
		end if;
	end process;

	-- Combinatorial
	StateMachine_Comb: process(state_reg, start_i, ctr_baud_reg, ctr_data_bit_reg, 
		baudrate_reg, delay_fifo_reg)
	begin
		-- Assign same value (prevent Latch infering)
		state_next			<= state_reg;
		tx_o_next			<= tx_o_reg;
		tx_done_next		<= '0';
		data_next			<= data_reg;
		ctr_baud_next		<= ctr_baud_reg;
		ctr_data_bit_next	<= ctr_data_bit_reg;
        baudrate_next       <= baudrate_reg;
		delay_fifo_next		<= delay_fifo_reg;

		-- State changes
		case(state_reg) is
			when IDLE_ST =>
				if start_i = '1' then
					state_next				<= GET_DATA_ST;
				end if;
				tx_o_next					<= '1';	
				tx_done_next				<= '0';

			when GET_DATA_ST =>
				state_next					<= SEND_DATA_ST;
				data_next					<= STOP_BIT & data_i & START_BIT;
				baudrate_next               <= baudrate_i;
				ctr_baud_next				<= (others => '0');
				ctr_data_bit_next			<= 0;
				
			when SEND_DATA_ST =>
			
				tx_o_next			<= data_reg(ctr_data_bit_reg);

				-- Baudrate Logic
				if ctr_baud_reg = unsigned(baudrate_reg) - 1 then
					if ctr_data_bit_reg = DATA_WIDTH + 1 then
						state_next			<= WAIT_ST;
						tx_done_next		<= '1';
					else
						ctr_data_bit_next	<= ctr_data_bit_reg + 1;
						ctr_baud_next		<= (others => '0');
					end if;
				else
					ctr_baud_next			<= ctr_baud_reg + 1;
				end if;
			
			when WAIT_ST =>
				delay_fifo_next				<= '1';
				if delay_fifo_reg = '1' then
					state_next				<= IDLE_ST;
					delay_fifo_next			<= '0';
				end if;

		end case;
	end process;

End Architecture;

