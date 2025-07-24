library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity triangular_generator is
    generic (
        CLK_FREQ        : integer := 100_000_000;  -- Clock de entrada (100 MHz)
        SWITCHING_FREQ  : integer := 10_000;       -- Frequência de chaveamento (10 kHz)
        DATA_WIDTH      : integer := 32            -- Largura de saída (para compatibilidade)
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        triangular: out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end triangular_generator;

architecture Behavioral of triangular_generator is
    -- FIXO em 8 bits para o contador interno
    constant TRIANGULAR_BITS : integer := 8;
    constant MAX_VALUE : signed(TRIANGULAR_BITS-1 downto 0) := to_signed(2**(TRIANGULAR_BITS-1) - 1, TRIANGULAR_BITS);   -- +127
    constant MIN_VALUE : signed(TRIANGULAR_BITS-1 downto 0) := to_signed(-2**(TRIANGULAR_BITS-1), TRIANGULAR_BITS);      -- -128
    
    -- Cálculo correto para 8 bits
    constant TOTAL_STEPS : integer := 2**TRIANGULAR_BITS;  -- 256 steps total
    constant CLK_PER_STEP : integer := CLK_FREQ / (SWITCHING_FREQ * TOTAL_STEPS);
    
    signal clk_counter : integer range 0 to CLK_PER_STEP := 0;
    signal counter_8bit: signed(TRIANGULAR_BITS-1 downto 0) := MIN_VALUE;
    signal count_up    : std_logic := '1';
    signal clk_enable  : std_logic := '0';
    
    -- Sinal para expansão
    signal triangular_scaled : signed(DATA_WIDTH-1 downto 0);
    
begin
    -- Divisor de clock
    process(clk, rst)
    begin
        if rst = '1' then
            clk_counter <= 0;
            clk_enable <= '0';
        elsif rising_edge(clk) then
            if CLK_PER_STEP > 1 then
                if clk_counter >= CLK_PER_STEP-1 then
                    clk_counter <= 0;
                    clk_enable <= '1';
                else
                    clk_counter <= clk_counter + 1;
                    clk_enable <= '0';
                end if;
            else
                clk_enable <= '1';
            end if;
        end if;
    end process;
    
    -- Gerador da onda triangular (8 bits)
    process(clk, rst)
    begin
        if rst = '1' then
            counter_8bit <= MIN_VALUE;
            count_up <= '1';
        elsif rising_edge(clk) then
            if clk_enable = '1' then
                if count_up = '1' then
                    if counter_8bit >= MAX_VALUE then
                        count_up <= '0';
                        counter_8bit <= counter_8bit - 1;
                    else
                        counter_8bit <= counter_8bit + 1;
                    end if;
                else
                    if counter_8bit <= MIN_VALUE then
                        count_up <= '1';
                        counter_8bit <= counter_8bit + 1;
                    else
                        counter_8bit <= counter_8bit - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    -- Escala de 8 bits para DATA_WIDTH bits
    process(counter_8bit)
        constant SHIFT_AMOUNT : integer := DATA_WIDTH - TRIANGULAR_BITS;
    begin
        if SHIFT_AMOUNT > 0 then
            -- Faz bit-shift para esquerda (multiplica por 2^SHIFT_AMOUNT)
            triangular_scaled <= resize(counter_8bit, DATA_WIDTH) sll SHIFT_AMOUNT;
        elsif SHIFT_AMOUNT < 0 then
            -- Faz bit-shift para direita (caso DATA_WIDTH < 8, improvável)
            triangular_scaled <= resize(counter_8bit srl (-SHIFT_AMOUNT), DATA_WIDTH);
        else
            -- Mesmo tamanho
            triangular_scaled <= resize(counter_8bit, DATA_WIDTH);
        end if;
    end process;
    
    triangular <= std_logic_vector(triangular_scaled);
    
end Behavioral;
