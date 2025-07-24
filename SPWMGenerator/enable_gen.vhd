library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity enable_generator is
    generic (
        CLK_FREQ    : integer := 100_000_000;  -- Frequência do clock (100 MHz)
        SINE_FREQ   : integer := 60;            -- Frequência desejada da senoide (60 Hz)
        TABLE_SIZE  : integer := 64             -- Tamanho da LUT (amostras por ciclo)
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        enable  : out std_logic                  -- Sinal de enable para a senoide
    );
end enable_generator;

architecture behavioral of enable_generator is
    -- Divisor para gerar o enable na frequência correta
    constant DIVISOR     : integer := CLK_FREQ / (SINE_FREQ * TABLE_SIZE);
    signal counter       : integer range 0 to DIVISOR-1 := 0;
    
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                counter <= 0;
                enable  <= '0';
            else
                if counter = DIVISOR-1 then
                    counter <= 0;           -- Reinicia o contador
                    enable  <= '1';         -- Gera um pulso de enable
                else
                    counter <= counter + 1; -- Incrementa o contador
                    enable  <= '0';
                end if;
            end if;
        end if;
    end process;
end behavioral;