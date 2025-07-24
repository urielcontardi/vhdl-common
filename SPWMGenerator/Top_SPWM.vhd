library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spwm_top is
    generic (
        CLK_FREQ        : integer := 200_000_000;
        SINE_FREQ       : integer := 50;
        SWITCHING_FREQ  : integer := 15_000;
        TABLE_SIZE      : integer := 1024;
        DATA_WIDTH      : integer := 48;           -- Pode ser qualquer valor
        CALC_WIDTH      : integer := 32
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        sine_out    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        triangular_out : out std_logic_vector(DATA_WIDTH-1 downto 0);
        spwm_out    : out std_logic
    );
end spwm_top;

architecture Behavioral of spwm_top is
    constant EFFECTIVE_WIDTH : integer := minimum(DATA_WIDTH, 32);
    
    signal sine_signal : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal triangular_signal : std_logic_vector(DATA_WIDTH-1 downto 0);
    
    -- Sinais para comparação (ambos em DATA_WIDTH completo)
    signal sine_for_comparison : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal triangular_for_comparison : std_logic_vector(DATA_WIDTH-1 downto 0);
    
begin
    -- Geradores (sem mudança)
    sine_gen : entity work.sine_top
        generic map (
            CLK_FREQ    => CLK_FREQ,
            SINE_FREQ   => SINE_FREQ,
            TABLE_SIZE  => TABLE_SIZE,
            DATA_WIDTH  => DATA_WIDTH,
            CALC_WIDTH  => CALC_WIDTH
        )
        port map (
            clk  => clk,
            rst  => rst,
            dout => sine_signal
        );
    
    triangular_gen : entity work.triangular_generator
        generic map (
            CLK_FREQ        => CLK_FREQ,
            SWITCHING_FREQ  => SWITCHING_FREQ,
            DATA_WIDTH      => EFFECTIVE_WIDTH  -- Gera em 32 bits máximo
        )
        port map (
            clk        => clk,
            rst        => rst,
            triangular => triangular_signal(EFFECTIVE_WIDTH-1 downto 0) -- Conecta diretamente
        );
    
    -- Comparador usa DATA_WIDTH completo
    spwm_comp : entity work.spwm_comparator
        generic map (
            DATA_WIDTH => DATA_WIDTH  -- Usa largura COMPLETA
        )
        port map (
            clk        => clk,
            rst        => rst,
            sine_wave  => sine_signal,           -- Senoide original completa
            triangular => triangular_signal,     -- Triangular expandida
            spwm_out   => spwm_out
        );
    
    -- Expansão correta da triangular para DATA_WIDTH
    process(triangular_signal)
    begin
        if DATA_WIDTH > EFFECTIVE_WIDTH then
            -- Padding com zeros nos bits mais significativos
            triangular_signal(DATA_WIDTH-1 downto EFFECTIVE_WIDTH) <= (others => triangular_signal(EFFECTIVE_WIDTH-1));
            -- triangular_signal(EFFECTIVE_WIDTH-1 downto 0) já conectado na port map
        end if;
    end process;
    
    -- Saídas diretas
    sine_out <= sine_signal;
    triangular_out <= triangular_signal;
    
end Behavioral;
