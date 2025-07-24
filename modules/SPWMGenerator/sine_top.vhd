library ieee;
use ieee.std_logic_1164.all;

entity sine_top is
    generic (
        CLK_FREQ    : integer := 100_000_000;  -- Clock de entrada (100 MHz)
        SINE_FREQ   : integer := 60;           -- Frequência da senoide (60 Hz)
        TABLE_SIZE  : integer := 1024;           -- Tamanho da LUT
        DATA_WIDTH  : integer := 32;            -- Resolução da senoide
        CALC_WIDTH  : integer := 32            -- Largura para cálculos internos
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        dout    : out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end sine_top;

architecture structural of sine_top is
    signal enable_int : std_logic; -- Sinal interno de enable
begin
    -- Contador para gerar o enable
    enable_inst: entity work.enable_generator
        generic map (
            CLK_FREQ    => CLK_FREQ,
            SINE_FREQ   => SINE_FREQ,
            TABLE_SIZE  => TABLE_SIZE
        )
        port map (
            clk     => clk,
            rst     => rst,
            enable  => enable_int
        );

    -- Gerador de senoide com LUT
    sine_gen_inst: entity work.sine_generator
        generic map (
            TABLE_SIZE  => TABLE_SIZE,
            DATA_WIDTH  => DATA_WIDTH,
            CALC_WIDTH  => CALC_WIDTH
        )
        port map (
            clk     => clk,
            rst     => rst,
            enable  => enable_int,
            dout    => dout
        );
end structural;
