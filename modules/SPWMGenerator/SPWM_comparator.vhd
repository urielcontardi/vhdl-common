library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spwm_comparator is
    generic (
        DATA_WIDTH : integer := 32
    );
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        sine_wave  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        triangular : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        spwm_out   : out std_logic
    );
end spwm_comparator;

architecture Behavioral of spwm_comparator is
    signal sine_signed : signed(DATA_WIDTH-1 downto 0);
    signal tri_signed  : signed(DATA_WIDTH-1 downto 0);
    
begin
    sine_signed <= signed(sine_wave);
    tri_signed <= signed(triangular);
    
    process(clk, rst)
    begin
        if rst = '1' then
            spwm_out <= '0';
        elsif rising_edge(clk) then
            if sine_signed > tri_signed then
                spwm_out <= '1';
            else
                spwm_out <= '0';
            end if;
        end if;
    end process;
    
end Behavioral;
