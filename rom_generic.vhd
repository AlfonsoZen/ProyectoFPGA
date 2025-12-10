library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rom_generic is
    generic (
        ADDR_WIDTH : integer := 10;           -- Cuántas direcciones tiene (bits)
        DATA_WIDTH : integer := 8;            -- De qué tamaño es cada dato
        MIF_FILE   : string  := "data.mif"    -- Archivo a leer (se cambia al usarlo)
    );
    port (
        clk      : in  std_logic;
        addr     : in  std_logic_vector(ADDR_WIDTH-1 downto 0); -- Dirección a leer
        q        : out std_logic_vector(DATA_WIDTH-1 downto 0)  -- Dato que sale
    );
end entity;

architecture rtl of rom_generic is
    -- Definimos la memoria como un arreglo
    type memory_t is array(0 to (2**ADDR_WIDTH)-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
    
    -- Esta señal 'rom' es la memoria física. 
    -- El atributo 'ram_init_file' le dice a Quartus: "Llénala con este archivo .mif"
    signal rom : memory_t;
    attribute ram_init_file : string;
    attribute ram_init_file of rom : signal is MIF_FILE;

begin

    process(clk)
    begin
        if rising_edge(clk) then
            -- En cada pulso de reloj, sacamos el dato de la dirección pedida
            q <= rom(to_integer(unsigned(addr)));
        end if;
    end process;

end rtl;