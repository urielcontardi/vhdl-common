-- Behavioral stub for the DSP multiplier used in simulation
-- This entity provides a simple registered signed multiplication
-- matching the interface expected by `BilinearSolverUnit.vhd`.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.BilinearSolverPkg.all;

entity BilienarSolverUnit_DSP is
    generic (
        LATENCY : natural := 7  -- pipeline stages (simulation latency)
    );
    port (
        CLK : in std_logic;
        A   : in std_logic_vector(FP_TOTAL_BITS - 1 downto 0);
        B   : in std_logic_vector(FP_TOTAL_BITS - 1 downto 0);
        P   : out std_logic_vector((2*FP_TOTAL_BITS)-1 downto 0)
    );
end entity;

architecture behavior of BilienarSolverUnit_DSP is
    -- Pipeline registers for the product
    type pipe_t is array (0 to LATENCY-1) of std_logic_vector((2*FP_TOTAL_BITS)-1 downto 0);
    signal pipe_reg : pipe_t := (others => (others => '0'));
begin

    process(CLK)
        variable product_v : signed((2*FP_TOTAL_BITS)-1 downto 0);
    begin
        if rising_edge(CLK) then
            product_v := signed(A) * signed(B);
            pipe_reg(0) <= std_logic_vector(product_v);
            for i in 1 to LATENCY-1 loop
                pipe_reg(i) <= pipe_reg(i-1);
            end loop;
        end if;
    end process;

    -- Combinatorial output: effective latency = exactly LATENCY cycles
    P <= pipe_reg(LATENCY-1);

end architecture;
