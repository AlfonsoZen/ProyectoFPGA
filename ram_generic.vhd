library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ram_generic is
    generic (
        ADDR_WIDTH : integer := 5;    -- Necesitamos guardar 30 valores, con 5 bits (32 huecos) sobra
        DATA_WIDTH : integer := 8     -- Guardamos valores de 8 bits
    );
    port (
        clk  : in  std_logic;
        we   : in  std_logic;                                 -- Write Enable (1 = Escribir, 0 = Leer)
        addr : in  std_logic_vector(ADDR_WIDTH-1 downto 0);   -- Dirección
        din  : in  std_logic_vector(DATA_WIDTH-1 downto 0);   -- Dato que entra (para guardar)
        q    : out std_logic_vector(DATA_WIDTH-1 downto 0)    -- Dato que sale (al leer)
    );
end entity;

architecture rtl of ram_generic is
    type memory_t is array(0 to (2**ADDR_WIDTH)-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
    
    -- Inicializamos en ceros
    signal ram : memory_t := (others => (others => '0'));

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if we = '1' then
                -- Si 'we' es 1, escribimos el dato en la memoria
                ram(to_integer(unsigned(addr))) <= din;
            end if;
            -- Siempre leemos el dato de la dirección actual (para que esté disponible al siguiente ciclo)
            q <= ram(to_integer(unsigned(addr)));
        end if;
    end process;

end rtl;