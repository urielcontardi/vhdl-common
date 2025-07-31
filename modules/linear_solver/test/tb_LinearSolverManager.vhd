--! \file		tb_LinearSolverManager.vhd
--!
--! \brief		
--!
--! \author		Vinícius Longo (longo.vinicius@gmail.com)
--! \date       17-07-2025
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
--!				
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.finish;

use work.SolverPkg.all; 

entity tb_LinearSolverManager is
end entity tb_LinearSolverManager;

architecture sim of tb_LinearSolverManager is

    --------------------------------------------------------------------------
    -- Constantes para o Testbench
    --------------------------------------------------------------------------
    constant N_SS_TB      : natural := 5;
    constant N_IN_TB      : natural := 2;
    constant CLK_PERIOD   : time    := 10 ns; -- Clock de 100 MHz
    constant MINIMUM_CYCLES : integer := 50;

    -- Matrizes e vetores constantes para os generics
    -- Usando valores simples para facilitar a verificação
    -- A = Identidade, B = Matriz de Uns, X_inicial = [1,2,3,4,5], U = [1,1]
    -- Equação: X(k+1) = I * X(k) + 1 * U
    -- Esperado: X(1) = X(0) + [2,2,2,2,2] -> [3,4,5,6,7]
    -- Esperado: X(2) = X(1) + [2,2,2,2,2] -> [5,6,7,8,9]
    
    -- Matriz A (Identidade)
    constant AMATRIX_TB : matrix_fp_t(0 to N_SS_TB - 1, 0 to N_SS_TB - 1) := (
        (to_fp(1.0), to_fp(1.0), to_fp(1.0), to_fp(1.0), to_fp(1.0)),
        (to_fp(2.0), to_fp(1.0), to_fp(1.0), to_fp(1.0), to_fp(1.0)),
        (to_fp(3.0), to_fp(1.0), to_fp(1.0), to_fp(1.0), to_fp(1.0)),
        (to_fp(4.0), to_fp(1.0), to_fp(1.0), to_fp(1.0), to_fp(1.0)),
        (to_fp(5.0), to_fp(1.0), to_fp(1.0), to_fp(1.0), to_fp(1.0))
    );
    
    -- Matriz B (Tudo 1.0)
    constant BMATRIX_TB : matrix_fp_t(0 to N_SS_TB - 1, 0 to N_IN_TB - 1) := (
        (to_fp(1.0), to_fp(1.0)),
        (to_fp(1.0), to_fp(1.0)),
        (to_fp(1.0), to_fp(1.0)),
        (to_fp(1.0), to_fp(1.0)),
        (to_fp(1.0), to_fp(1.0))
    );

    -- Condição Inicial de X
    constant XVEC_INITIAL_TB : vector_fp_t(0 to N_SS_TB - 1) := (
        to_fp(1.0), to_fp(1.0), to_fp(1.0), to_fp(1.0), to_fp(1.0)
    );


    -- Vetor de Entrada U (constante)
    constant UVECTOR_TB : vector_fp_t(0 to N_IN_TB - 1) := (
        to_fp(1.0), to_fp(1.0)
    );
    
    --------------------------------------------------------------------------
    -- Sinais para conectar ao UUT (Manager)
    --------------------------------------------------------------------------
    signal sysclk_tb          : std_logic := '0';
    signal reset_n            : std_logic := '0';
    signal start_i_tb          : std_logic := '0';
    signal Uvector_i_tb       : vector_fp_t(0 to N_IN_TB - 1) := UVECTOR_TB;
    signal Xvec_current_o_tb  : vector_fp_t(0 to N_SS_TB - 1);
    signal busy_o_tb          : std_logic := '0';

begin

    --------------------------------------------------------------------------
    -- Instanciação do Unit Under Test (UUT)
    --------------------------------------------------------------------------
    UUT : entity work.LinearSolverManager
    generic map (
        N_SS            => N_SS_TB,
        N_IN            => N_IN_TB
    )
    port map (
        sysclk          => sysclk_tb,
        reset_n         => reset_n,
        init_calc_i     => start_i_tb,
        Amatrix_i       => AMATRIX_TB,
        Bmatrix_i       => BMATRIX_TB,
        Xvec_initial    => XVEC_INITIAL_TB,
        Uvector_i       => Uvector_i_tb,
        Xvec_current_o  => Xvec_current_o_tb,
        busy_o          => busy_o_tb
    );


    --------------------------------------------------------------------------
    -- Geração de Clock
    --------------------------------------------------------------------------
    clk_process: process
    begin
        
        sysclk_tb <= '0';
        wait for CLK_PERIOD / 2;
        sysclk_tb <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    --------------------------------------------------------------------------
    -- Geração de Reset_n
    --------------------------------------------------------------------------
    reset_process: process
    begin
        wait until rising_edge(sysclk_tb);
        wait for CLK_PERIOD * 10;
        reset_n <= '1';

    end process;

    --------------------------------------------------------------------------
    -- Estímulos de Teste
    --------------------------------------------------------------------------
    stimulus_process: process

    begin
        wait until rising_edge(sysclk_tb);
        start_i_tb <= '0';
        wait for MINIMUM_CYCLES * CLK_PERIOD;
        start_i_tb <= '1'; 
        wait for CLK_PERIOD;
        start_i_tb <= '0';
        wait for MINIMUM_CYCLES * CLK_PERIOD;
        start_i_tb <= '1';
        wait for CLK_PERIOD;
        start_i_tb <= '0';
        wait for MINIMUM_CYCLES * CLK_PERIOD;
        start_i_tb <= '1'; 
        wait for CLK_PERIOD;
        start_i_tb <= '0';
        wait for MINIMUM_CYCLES * CLK_PERIOD;
        start_i_tb <= '1';
        wait for CLK_PERIOD;
        start_i_tb <= '0';
        wait for MINIMUM_CYCLES * CLK_PERIOD;
        finish;
    end process;

end architecture sim;