library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mac is
    generic (
        DATA_WIDTH : integer := 8;
        ACC_WIDTH  : integer := 32 -- Acumulador de 32 bits para evitar overflow
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        enable    : in  std_logic;
        pixel_in  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        weight_in : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        result    : out std_logic_vector(ACC_WIDTH-1 downto 0)
    );
end entity;

architecture rtl of mac is
    -- CORRECCIÓN: 9 bits (pixel) + 8 bits (peso) = 17 bits.
    -- Declaramos 16 downto 0 (17 bits en total) para que coincida exactamente.
    signal product     : signed(16 downto 0); 
    signal accumulator : signed(ACC_WIDTH-1 downto 0);
    
begin
    process(clk, reset)
    begin
        if reset = '1' then
            accumulator <= (others => '0');
            product     <= (others => '0');
        elsif rising_edge(clk) then
            if enable = '1' then
                -- Operación:
                -- '0' & pixel_in (9 bits unsigned) * weight_in (8 bits signed) = 17 bits signed
                product <= signed('0' & pixel_in) * signed(weight_in);
                
                -- Sumamos al acumulador de 32 bits (resize maneja la extensión de signo)
                accumulator <= accumulator + resize(product, ACC_WIDTH);
            end if;
        end if;
    end process;

    result <= std_logic_vector(accumulator);

end rtl;