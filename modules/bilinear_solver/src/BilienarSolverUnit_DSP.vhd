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
    signal A_s : signed(FP_TOTAL_BITS - 1 downto 0);
    signal B_s : signed(FP_TOTAL_BITS - 1 downto 0);
    signal product_comb : signed((2*FP_TOTAL_BITS)-1 downto 0);

    -- Pipeline registers for the product
    type pipe_t is array (natural range <>) of std_logic_vector((2*FP_TOTAL_BITS)-1 downto 0);
    signal pipe_reg : pipe_t(0 to LATENCY-1) := (others => (others => '0'));
begin

    -- Combinational product (computed each cycle, latched into pipeline)
    product_comb <= resize(A_s, product_comb'length) * resize(B_s, product_comb'length);

    process(CLK)
    begin
        if rising_edge(CLK) then
            A_s <= signed(A);
            B_s <= signed(B);

            -- Shift pipeline: first stage gets current product
            if LATENCY > 0 then
                pipe_reg(0) <= std_logic_vector(product_comb);
                for i in 1 to LATENCY-1 loop
                    pipe_reg(i) <= pipe_reg(i-1);
                end loop;
                P <= pipe_reg(LATENCY-1);
            else
                -- No pipeline requested: output combinational product registered
                P <= std_logic_vector(product_comb);
            end if;
        end if;
    end process;
end architecture;
