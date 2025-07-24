--! \file		LinearSolver_Manager.vhd
--!
--! \brief		
--!
--! \author		Vinícius de Carvalho Monteiro Longo (longo.vinicius@gmail.com)
--! \date       22-07-2025
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
--!				- 1.0	22-07-2025	<longo.vinicius@gmail.com>
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
use work.Solver_pkg.all;

--------------------------------------------------------------------------
-- Entity declaration
--------------------------------------------------------------------------
entity LinearSolver_Manager is
    generic (
        N_SS                : natural := 5;   
        N_IN                : natural := 2  
    );
    port (
        sysclk              : in std_logic;
        reset_n             : in std_logic;
        init_calc_i         : in std_logic;
        Amatrix_i           : in matrix_fp_t(0 to N_SS - 1, 0 to N_SS - 1);
        Bmatrix_i           : in matrix_fp_t(0 to N_SS - 1, 0 to N_IN - 1); 
        Xvec_initial        : in vector_fp_t(0 to N_SS - 1); 
        Uvector_i           : in vector_fp_t(0 to N_IN - 1);
        Xvec_current_o      : out vector_fp_t(0 to N_SS - 1);
        busy_o              : out std_logic

    );
end entity;

--------------------------------------------------------------------------
-- Architecture
--------------------------------------------------------------------------
architecture arch of LinearSolver_Manager is
    
    type state_t is (S_IDLE, S_BUSY);
    signal current_state        : state_t := S_IDLE;
    signal busy_sig             : std_logic;
    signal X_next_sig           : vector_fp_t(0 to N_SS - 1);
    signal X_current_sig        : vector_fp_t(0 to N_SS - 1);

begin

    LSH: entity work.LinearSolver_Handler
    generic map(
        N_SS                => N_SS,
        N_IN                => N_IN
    )
    port map(
        sysclk              => sysclk,
        start_i             => init_calc_i,
        Amatrix_i           => Amatrix_i,
        Xvec_i              => X_current_sig, 
        Bmatrix_i           => Bmatrix_i,
        Uvec_i              => Uvector_i,
        stateResultVec_o    => X_next_sig,   
        busy_o              => busy_sig
    );

    State_Machine_Process: process(reset_n, sysclk)
    begin 
        if reset_n = '0' then 
            X_current_sig <= Xvec_initial;
        elsif rising_edge(sysclk) then
            case current_state is
                when S_IDLE =>
                    if init_calc_i = '1' then 
                        current_state <= S_BUSY;
                    end if;
                when S_BUSY =>
                    if busy_sig = '0' then 
                        X_current_sig <= X_next_sig;
                        current_state <= S_IDLE;
                    end if;
            end case;
        end if;
    end process; 
    
    Xvec_current_o <=  X_current_sig;           
    busy_o         <=  busy_sig;

end ;