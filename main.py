import tensorflow as tf
import numpy as np
import os

# --- CONFIGURACIÓN OPTIMIZADA ---
# Usamos potencias de 2 para facilitar los shifts en VHDL
# Entrada: 0.0-1.0 -> 0-128 (7 bits, cabe en 8 bits unsigned)
INPUT_SCALE = 128.0 
# Pesos: -1.0-1.0 -> -128-127 (8 bits signed)
WEIGHT_SCALE = 128.0

def create_mif_file(filename, data, width=8, depth=1024):
    with open(filename, 'w') as f:
        f.write(f"DEPTH = {depth};\n")
        f.write(f"WIDTH = {width};\n")
        f.write("ADDRESS_RADIX = DEC;\n")
        f.write("DATA_RADIX = HEX;\n") 
        f.write("CONTENT\n")
        f.write("BEGIN\n")
        for i, val in enumerate(data):
            if val < 0: val = (1 << width) + val 
            hex_val = f"{val:0{width//4}X}" 
            f.write(f"{i} : {hex_val};\n")
        if len(data) < depth:
            f.write(f"[{len(data)}..{depth-1}] : 00;\n")
        f.write("END;\n")
    print(f"Generado: {filename}")

def main():
    print("1. Cargando MNIST...")
    mnist = tf.keras.datasets.mnist
    (x_train, y_train), (x_test, y_test) = mnist.load_data()
    
    # Normalizar 0-1
    x_train, x_test = x_train / 255.0, x_test / 255.0 

    # --- CORRECCIÓN DEL ERROR ---
    # Aplanar las imágenes (de 28x28 a 784 entradas)
    # Esto faltaba en la versión anterior y causaba el ValueError
    x_train = x_train.reshape((-1, 784))
    x_test = x_test.reshape((-1, 784))

    print("2. Entrenando Modelo...")
    model = tf.keras.models.Sequential([
        tf.keras.layers.Dense(30, activation='relu', input_shape=(784,)),
        tf.keras.layers.Dense(10, activation='softmax')
    ])
    model.compile(optimizer='adam', loss='sparse_categorical_crossentropy', metrics=['accuracy'])
    
    # Entrenamos más épocas para asegurar convergencia robusta
    model.fit(x_train, y_train, epochs=10, validation_data=(x_test, y_test))

    print("3. Exportando Pesos y Bias...")
    w1, b1 = model.layers[0].get_weights() 
    w2, b2 = model.layers[1].get_weights()

    # --- CUANTIZACIÓN INTELIGENTE ---
    w1_int = np.clip(np.round(w1 * WEIGHT_SCALE), -128, 127).astype(int)
    b1_int = np.clip(np.round(b1 * WEIGHT_SCALE), -128, 127).astype(int)
    w2_int = np.clip(np.round(w2 * WEIGHT_SCALE), -128, 127).astype(int)
    b2_int = np.clip(np.round(b2 * WEIGHT_SCALE), -128, 127).astype(int)

    # Transponemos pesos W para lectura lineal [Neurona][Pixel]
    create_mif_file("rom_w1.mif", w1_int.T.flatten(), width=8, depth=32768)
    create_mif_file("rom_b1.mif", b1_int.flatten(), width=8, depth=32)
    create_mif_file("rom_w2.mif", w2_int.T.flatten(), width=8, depth=512)
    create_mif_file("rom_b2.mif", b2_int.flatten(), width=8, depth=32)
    
    # --- PRUEBA AUTOMÁTICA ---
    # Busca un número específico para probar (CAMBIA ESTE VALOR PARA PROBAR OTROS)
    OBJETIVO = 5
    # Buscar índice
    indices = np.where(y_test == OBJETIVO)[0]
    if len(indices) > 0:
        idx = indices[0]
    else:
        idx = 0
        print(f"Advertencia: No se encontró el número {OBJETIVO}, usando índice 0")
    
    img = x_test[idx] # Ya está aplanada (784,)
    
    # ESCALA CRÍTICA: Usamos 128 en lugar de 255 para la entrada
    # img ya viene de 0.0 a 1.0. Multiplicamos por 128.
    img_int = np.clip(np.round(img * INPUT_SCALE), 0, 127).astype(int)
    create_mif_file("img_prueba.mif", img_int, width=8, depth=1024)
    print(f"\nImagen exportada: {y_test[idx]} (Índice {idx})")
    
    # --- SIMULACIÓN VERIFICADA ---
    print("\n--- SIMULACIÓN BIT-EXACTA ---")
    
    # Capa 1
    hidden_out = []
    for i in range(30):
        # img_int es (784,), w1_int.T[i] es (784,)
        acc = np.dot(img_int, w1_int.T[i]) 
        acc += (b1_int[i] << 7)            
        if acc < 0: val = 0                
        else: val = acc >> 7               
        if val > 127: val = 127            
        hidden_out.append(val)
    
    # Capa 2
    final_out = []
    for i in range(10):
        acc = np.dot(hidden_out, w2_int.T[i])
        acc += (b2_int[i] << 7)
        final_out.append(acc)

    print(f"Valores crudos: {final_out}")
    print(f"Ganador esperado: {np.argmax(final_out)}")

if __name__ == "__main__":
    main()