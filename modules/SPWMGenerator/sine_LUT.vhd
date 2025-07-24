library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity sine_generator is
    generic (
        TABLE_SIZE  : integer := 64;   -- Tamanho da LUT
        DATA_WIDTH  : integer := 8;    -- Largura dos dados de saída
        CALC_WIDTH  : integer := 32    -- Largura para cálculos internos (máximo 32)
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        enable  : in  std_logic;
        dout    : out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end sine_generator;

architecture behavioral of sine_generator is
    -- Determina a largura efetiva para cálculos
    constant EFFECTIVE_WIDTH : integer := minimum(DATA_WIDTH, CALC_WIDTH);
    
    -- Declaração do tipo da LUT
    type sine_lut_type is array (0 to TABLE_SIZE-1) of integer;
    
    -- Função para inicializar a LUT (executada durante a elaboração)
    function init_sine_lut return sine_lut_type is
        variable temp_lut : sine_lut_type;
        variable angle    : real;
        variable sin_val  : real;
        variable amp      : real := real(2**(EFFECTIVE_WIDTH-1) - 1); -- Amplitude segura
    begin
        for i in 0 to TABLE_SIZE-1 loop
            angle := real(i) * ((2.0 * MATH_PI) / real(TABLE_SIZE));
            sin_val := sin(angle);
            temp_lut(i) := integer(sin_val * amp);
        end loop;
        return temp_lut;
    end function;

    -- Declaração da LUT como constante
    constant SINE_LUT : sine_lut_type := init_sine_lut;
    
    -- Registrador para índice da LUT
    signal lut_index : integer range 0 to TABLE_SIZE-1 := 0;
    
    -- Sinal intermediário para o valor da LUT
    signal lut_value : signed(EFFECTIVE_WIDTH-1 downto 0);
    signal resized_value : signed(DATA_WIDTH-1 downto 0);

begin
    -- Processo para atualizar o índice
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                lut_index <= 0;
            elsif enable = '1' then
                -- Atualiza o índice (circular)
                lut_index <= (lut_index + 1) mod TABLE_SIZE;
            end if;
        end if;
    end process;
    
    -- Obter valor da LUT
    lut_value <= to_signed(SINE_LUT(lut_index), EFFECTIVE_WIDTH);
    
    -- Processo para redimensionar e ajustar a saída
    GEN_SAME_SIZE: if DATA_WIDTH <= EFFECTIVE_WIDTH generate
        -- Se DATA_WIDTH for menor ou igual a EFFECTIVE_WIDTH, apenas pegue os bits mais significativos
        resized_value <= lut_value(EFFECTIVE_WIDTH-1 downto EFFECTIVE_WIDTH-DATA_WIDTH);
    end generate;
    
    GEN_LARGER_SIZE: if DATA_WIDTH > EFFECTIVE_WIDTH generate
        -- Se DATA_WIDTH for maior que EFFECTIVE_WIDTH, faça um resize inteligente
        -- Isso mantém o bit de sinal e expande os bits fracionários
        resized_value <= resize(lut_value, DATA_WIDTH);
    end generate;
    
    -- Atribuir à saída
    dout <= std_logic_vector(resized_value);

end behavioral;
