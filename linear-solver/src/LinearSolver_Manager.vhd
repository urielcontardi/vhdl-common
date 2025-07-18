library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.Solver_pkg.all;

entity LinearSolver_Manager is
    generic (
        N_SS                : natural := 5;   
        N_IN                : natural := 2  
    );
    port (
        sysclk              : in std_logic;
        reset_n             : in std_logic;
        init_calc_i         : in std_logic;
        Amatrix_i             : in matrix_fp_t(0 to N_SS - 1, 0 to N_SS - 1);
        Bmatrix_i             : in matrix_fp_t(0 to N_SS - 1, 0 to N_IN - 1); 
        Xvec_initial        : in vector_fp_t(0 to N_SS - 1); 
        Uvector_i           : in vector_fp_t(0 to N_IN - 1);
        Xvec_current_o      : out vector_fp_t(0 to N_SS - 1)

    );
end entity;

architecture arch of LinearSolver_Manager is

    signal start_i_sig        : std_logic;
    signal busy_sig           : std_logic;
    signal X_next_sig         : vector_fp_t(0 to N_SS - 1);
    signal X_current_sig      : vector_fp_t(0 to N_SS - 1) := Xvec_initial;

    type state_t is (S_IDLE, S_BUSY);
    signal current_state    : state_t := S_IDLE;

begin

    LSH: entity work.LinearSolver_Handler
    generic map(
        N_SS => N_SS,
        N_IN => N_IN
    )
    port map(
        sysclk      => sysclk,
        start_i     => start_i_sig,
        Amatrix_i   => Amatrix_i,
        Xvec_i      => X_current_sig, 
        Bmatrix_i   => Bmatrix_i,
        Uvec_i      => Uvector_i,
        Xvec_next_o => X_next_sig,   
        busy_o      => busy_sig
    );

    State_Machine_Process: process(sysclk)
    begin
        if reset_n = '0' then
            current_state <= S_IDLE;
            X_current_sig <= Xvec_initial;
            start_i_sig <= '0';
        elsif rising_edge(sysclk) then
            case current_state is
                when S_IDLE =>
                    start_i_sig <= '0';
                    if init_calc_i = '1' and busy_sig = '0' then
                        start_i_sig <= '1'; 
                        current_state <= S_BUSY;
                    end if;                   
                when S_BUSY =>
                    start_i_sig <= '0';
                    if busy_sig = '0' then
                        X_current_sig <= X_next_sig; 
                        current_state <= S_IDLE; 
                    end if;    
            end case;
        end if;
    end process State_Machine_Process;

    Xvec_current_o <= X_current_sig;
    

end arch;