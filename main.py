import tensorflow as tf
import numpy as np
import os

# --- CONFIGURACIÓN ---
# Usaremos 8 bits para los pesos.
# Rango de 8 bits con signo: -128 a 127.
# Factor de escala: Decidimos que el número 1.0 (float) será representado como 64 (entero).
# Esto nos da espacio para números hasta +/- 2.0 antes de desbordar, o mayor precisión.
# Para este ejemplo usaremos SCALE = 128 (así 0.99 es aprox 127).
SCALE_FACTOR = 128.0 

def create_mif_file(filename, data, width=8, depth=1024):
    """
    Genera un archivo .mif para la memoria de la FPGA (Quartus).
    data: lista de enteros.
    """
    with open(filename, 'w') as f:
        f.write(f"DEPTH = {depth};\n")
        f.write(f"WIDTH = {width};\n")
        f.write("ADDRESS_RADIX = DEC;\n")
        f.write("DATA_RADIX = HEX;\n") # Hexadecimal es más fácil de leer para depurar
        f.write("CONTENT\n")
        f.write("BEGIN\n")
        
        for i, val in enumerate(data):
            # Asegurar que el valor encaje en 'width' bits (complemento a 2)
            if val < 0:
                val = (1 << width) + val # Convertir -1 a 0xFF por ejemplo
            
            # Formato: Dirección : Dato;
            # Hexadecimal limpio
            hex_val = f"{val:0{width//4}X}" 
            f.write(f"{i} : {hex_val};\n")
            
        # Rellenar con ceros si sobran direcciones
        if len(data) < depth:
            f.write(f"[{len(data)}..{depth-1}] : 00;\n")
            
        f.write("END;\n")
    print(f"Archivo generado: {filename} (Datos: {len(data)})")

def main():
    print("1. Cargando datos MNIST...")
    mnist = tf.keras.datasets.mnist
    (x_train, y_train), (x_test, y_test) = mnist.load_data()
    
    # Normalizar imágenes: de 0-255 a 0.0-1.0
    x_train, x_test = x_train / 255.0, x_test / 255.0
    
    # Aplanar las imágenes (de 28x28 a 784 entradas)
    x_train = x_train.reshape((-1, 784))
    x_test = x_test.reshape((-1, 784))

    print("2. Creando modelo MLP (784 -> 30 -> 10)...")
    model = tf.keras.models.Sequential([
        # Capa Oculta: 30 neuronas, activación Sigmoid (como pide el PDF)
        tf.keras.layers.Dense(30, activation='sigmoid', input_shape=(784,)),
        # Capa Salida: 10 neuronas, activación Softmax (para entrenamiento)
        # Nota: En la FPGA la softmax suele omitirse y solo se busca el máximo.
        tf.keras.layers.Dense(10, activation='softmax')
    ])

    model.compile(optimizer='adam',
                  loss='sparse_categorical_crossentropy',
                  metrics=['accuracy'])

    print("3. Entrenando (esto puede tardar unos segundos)...")
    model.fit(x_train, y_train, epochs=5, validation_data=(x_test, y_test))

    print("\n4. Extrayendo y cuantizando pesos...")
    # Obtener pesos y bias como listas de numpy
    # Layer 0 es la oculta (784 -> 30)
    w1, b1 = model.layers[0].get_weights() 
    # Layer 1 es la salida (30 -> 10)
    w2, b2 = model.layers[1].get_weights()

    # --- CUANTIZACIÓN (Conversión Float -> Entero) ---
    # Multiplicamos por SCALE_FACTOR y redondeamos
    w1_int = np.round(w1 * SCALE_FACTOR).astype(int)
    b1_int = np.round(b1 * SCALE_FACTOR).astype(int)
    w2_int = np.round(w2 * SCALE_FACTOR).astype(int)
    b2_int = np.round(b2 * SCALE_FACTOR).astype(int)

    # Validar rangos (para 8 bits con signo: -128 a 127)
    # Si se pasan, los recortamos (clipping). 
    # Es importante revisar si muchos valores se recortan.
    min_val, max_val = -128, 127
    w1_int = np.clip(w1_int, min_val, max_val)
    b1_int = np.clip(b1_int, min_val, max_val)
    w2_int = np.clip(w2_int, min_val, max_val)
    b2_int = np.clip(b2_int, min_val, max_val)

    print(f"Rango de pesos W1 detectado: {w1_int.min()} a {w1_int.max()}")

    # --- EXPORTACIÓN A ARCHIVOS .MIF ---
    # Para la FPGA, necesitamos organizar la memoria linealmente.
    # Estrategia: Guardar todo W1 en un archivo, B1 en otro, etc.
    
    # MIF 1: Pesos Capa Oculta (784 entradas x 30 neuronas = 23,520 datos)
    # Nota: Aplanamos w1. En VHDL leeremos secuencialmente.
    create_mif_file("rom_w1.mif", w1_int.flatten(), width=8, depth=32768) # Depth debe ser potencia de 2 mayor a datos
    
    # MIF 2: Bias Capa Oculta (30 datos)
    create_mif_file("rom_b1.mif", b1_int.flatten(), width=8, depth=32)

    # MIF 3: Pesos Capa Salida (30 entradas x 10 neuronas = 300 datos)
    create_mif_file("rom_w2.mif", w2_int.flatten(), width=8, depth=512)

    # MIF 4: Bias Capa Salida (10 datos)
    create_mif_file("rom_b2.mif", b2_int.flatten(), width=8, depth=32)
    
    # OPCIONAL: Exportar una imagen de prueba para usarla en la simulación VHDL
    imagen_prueba = x_test[0] # Tomamos la primera imagen del test
    imagen_int = np.round(imagen_prueba * 255).astype(int) # Escala 0-255
    create_mif_file("img_prueba.mif", imagen_int, width=8, depth=1024)
    print(f"Imagen de prueba exportada. Es un número: {y_test[0]}")

    print("\n¡Listo! Archivos .mif generados. Cárgalos en Quartus.")

if __name__ == "__main__":
    main()