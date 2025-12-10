library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity neural_network is
    port (
        clk      : in  std_logic;
        reset_n  : in  std_logic;
        leds     : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of neural_network is

    type state_t is (IDLE, LAYER1_COMPUTE, LAYER1_SAVE, LAYER2_COMPUTE, CHECK_MAX, FINISH);
    signal state : state_t;

    -- Señales y Contadores
    signal cnt_pixels  : integer range 0 to 1023;
    signal cnt_neuron1 : integer range 0 to 31;
    signal cnt_neuron2 : integer range 0 to 15;
    
    -- Buses de datos
    signal pixel_val, w1_val, w2_val, ram_out : std_logic_vector(7 downto 0);
    signal b1_val, b2_val : std_logic_vector(7 downto 0); -- Nuevas señales para Bias
    
    signal mac_op_a, mac_op_b : std_logic_vector(7 downto 0);
    signal mac_reset, mac_enable : std_logic;
    signal mac_result : std_logic_vector(31 downto 0); -- AHORA ES 32 BITS
    
    signal ram_we : std_logic;
    signal ram_addr : std_logic_vector(4 downto 0);
    signal ram_din : std_logic_vector(7 downto 0);

    signal max_val : signed(31 downto 0); -- 32 bits
    signal max_idx : integer range 0 to 15;

    -- Componentes
    component rom_generic is
        generic (ADDR_WIDTH : integer; DATA_WIDTH : integer; MIF_FILE : string);
        port (clk : in std_logic; addr : in std_logic_vector; q : out std_logic_vector);
    end component;

    component ram_generic is
        generic (ADDR_WIDTH : integer; DATA_WIDTH : integer);
        port (clk : in std_logic; we : in std_logic; addr : in std_logic_vector; din : in std_logic_vector; q : out std_logic_vector);
    end component;

    component mac is
        generic (DATA_WIDTH : integer; ACC_WIDTH : integer);
        port (clk : in std_logic; reset : in std_logic; enable : in std_logic; pixel_in : in std_logic_vector; weight_in : in std_logic_vector; result : out std_logic_vector);
    end component;
    
    -- Direccionamiento
    signal addr_img : std_logic_vector(9 downto 0);
    signal addr_w1  : std_logic_vector(14 downto 0);
    signal addr_w2  : std_logic_vector(9 downto 0);
    -- Direcciones para Bias (usamos los contadores de neurona)
    signal addr_b1  : std_logic_vector(4 downto 0);
    signal addr_b2  : std_logic_vector(4 downto 0);

begin

    -- 1. Memorias (Ahora incluimos Bias)
    IMG_ROM : rom_generic generic map (10, 8, "img_prueba.mif") port map (clk, addr_img, pixel_val);
    W1_ROM  : rom_generic generic map (15, 8, "rom_w1.mif")     port map (clk, addr_w1, w1_val);
    B1_ROM  : rom_generic generic map (5, 8,  "rom_b1.mif")     port map (clk, addr_b1, b1_val); -- Bias 1
    
    W2_ROM  : rom_generic generic map (10, 8, "rom_w2.mif")     port map (clk, addr_w2, w2_val);
    B2_ROM  : rom_generic generic map (5, 8,  "rom_b2.mif")     port map (clk, addr_b2, b2_val); -- Bias 2
    
    HIDDEN_RAM : ram_generic generic map (5, 8)                 port map (clk, ram_we, ram_addr, ram_din, ram_out);

    -- 2. Conexiones Físicas
    -- Direcciones Bias siempre apuntan a la neurona actual
    addr_b1 <= std_logic_vector(to_unsigned(cnt_neuron1, 5));
    addr_b2 <= std_logic_vector(to_unsigned(cnt_neuron2, 5));

    -- MUX MAC
    process(state, pixel_val, w1_val, ram_out, w2_val, cnt_pixels)
    begin
        if state = LAYER1_COMPUTE then
            if cnt_pixels >= 785 then 
                mac_op_a <= (others => '0'); mac_op_b <= (others => '0');
            else
                mac_op_a <= pixel_val; mac_op_b <= w1_val;
            end if;
        elsif state = LAYER2_COMPUTE then
            if cnt_pixels >= 31 then 
                mac_op_a <= (others => '0'); mac_op_b <= (others => '0');
            else
                mac_op_a <= ram_out; mac_op_b <= w2_val;
            end if;
        else
            mac_op_a <= (others => '0'); mac_op_b <= (others => '0');
        end if;
    end process;

    -- Instancia MAC 32 bits
    MAC_UNIT : mac generic map (8, 32) port map (clk, mac_reset, mac_enable, mac_op_a, mac_op_b, mac_result);

    -- 3. FSM MEJORADA
    process(clk, reset_n)
        variable acc_full : signed(31 downto 0);
        variable bias_shifted : signed(31 downto 0);
        variable result_scaled : signed(31 downto 0);
    begin
        if reset_n = '0' then
            state <= IDLE;
            cnt_pixels <= 0; cnt_neuron1 <= 0; cnt_neuron2 <= 0;
            leds <= "10101010";
            max_val <= to_signed(-2000000000, 32);
            max_idx <= 0;
            ram_we <= '0'; mac_reset <= '1';
            
        elsif rising_edge(clk) then
            ram_we <= '0'; -- Default
            
            case state is
                when IDLE =>
                    state <= LAYER1_COMPUTE;
                    cnt_pixels <= 0; cnt_neuron1 <= 0;
                    mac_reset <= '1'; leds <= "10101010";
                    
                -- ================= CAPA 1 =================
                when LAYER1_COMPUTE =>
                    mac_reset <= '0'; mac_enable <= '1';
                    if cnt_pixels < 786 then 
                        cnt_pixels <= cnt_pixels + 1;
                    else
                        state <= LAYER1_SAVE; mac_enable <= '0';
                    end if;
                    
                when LAYER1_SAVE =>
                    -- LÓGICA DE BIAS Y ESCALA
                    -- 1. Tomar Acumulador (Scale 2^14)
                    acc_full := signed(mac_result);
                    
                    -- 2. Tomar Bias (Scale 2^7) y convertir a Scale 2^14 (Shift Left 7)
                    bias_shifted := resize(signed(b1_val), 32) sll 7;
                    
                    -- 3. Sumar
                    acc_full := acc_full + bias_shifted;
                    
                    -- 4. ReLU (Si < 0 -> 0)
                    if acc_full < 0 then
                        ram_din <= (others => '0');
                    else
                        -- 5. Recovery: Shift Right 7 para volver a Scale 2^7
                        result_scaled := acc_full srl 7; -- Shift lógico o aritmético
                        
                        -- 6. Saturación a 8 bits (0..127)
                        if result_scaled > 127 then 
                           ram_din <= "01111111";
                        else
                           ram_din <= std_logic_vector(result_scaled(7 downto 0)); 
                        end if;
                    end if;
                    
                    ram_addr <= std_logic_vector(to_unsigned(cnt_neuron1, 5));
                    ram_we <= '1';
                    
                    if cnt_neuron1 < 29 then
                        cnt_neuron1 <= cnt_neuron1 + 1; cnt_pixels <= 0; mac_reset <= '1';
                        state <= LAYER1_COMPUTE;
                    else
                        state <= LAYER2_COMPUTE;
                        cnt_neuron2 <= 0; cnt_pixels <= 0; mac_reset <= '1';
                        max_val <= to_signed(-2000000000, 32);
                    end if;

                -- ================= CAPA 2 =================
                when LAYER2_COMPUTE =>
                    if cnt_pixels < 30 then
                        ram_addr <= std_logic_vector(to_unsigned(cnt_pixels, 5));
                    else
                        ram_addr <= (others => '0');
                    end if;
                    mac_reset <= '0'; mac_enable <= '1';
                    
                    if cnt_pixels < 32 then
                        cnt_pixels <= cnt_pixels + 1;
                    else
                        state <= CHECK_MAX; mac_enable <= '0';
                    end if;
                    
                when CHECK_MAX =>
                    -- Sumar Bias también en la salida!
                    acc_full := signed(mac_result);
                    bias_shifted := resize(signed(b2_val), 32) sll 7;
                    acc_full := acc_full + bias_shifted;
                    
                    -- Comparación de magnitud
                    if acc_full > max_val then
                        max_val <= acc_full;
                        max_idx <= cnt_neuron2;
                    end if;
                    
                    if cnt_neuron2 < 9 then
                        cnt_neuron2 <= cnt_neuron2 + 1; cnt_pixels <= 0; mac_reset <= '1';
                        state <= LAYER2_COMPUTE;
                    else
                        state <= FINISH;
                    end if;

                when FINISH =>
                    leds <= std_logic_vector(to_unsigned(max_idx, 8));
                    
                when others => state <= IDLE;
            end case;
        end if;
    end process;
    
    -- Direcciones ROM
    addr_img <= std_logic_vector(to_unsigned(cnt_pixels, 10)) when cnt_pixels < 784 else (others => '0');
    addr_w1  <= std_logic_vector(to_unsigned((cnt_neuron1 * 784) + cnt_pixels, 15)) when cnt_pixels < 784 else (others => '0');
    addr_w2  <= std_logic_vector(to_unsigned((cnt_neuron2 * 30) + cnt_pixels, 10)) when cnt_pixels < 30 else (others => '0');

end rtl;