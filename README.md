# Entrenamiento y Exportación de Pesos para MLP en FPGA (MNIST)

Este repositorio contiene el script de Python necesario para entrenar una Red Neuronal (Perceptrón Multicapa) y exportar sus pesos y sesgos (biases) en formato hexadecimal (.mif) para ser implementados en una FPGA (Intel DE10-Lite).

## Descripción del Proyecto

El objetivo es entrenar una red neuronal con la arquitectura **784-30-10** utilizando el conjunto de datos MNIST (dígitos escritos a mano). Posteriormente, el script realiza un proceso de **cuantización** para convertir los números flotantes en enteros de 8 bits (Aritmética de Punto Fijo), requisito indispensable para la implementación eficiente en hardware (VHDL).

### Arquitectura de la Red
* **Entrada:** 784 neuronas (imágenes de 28x28 píxeles aplanadas).
* **Capa Oculta:** 30 neuronas.
* **Capa de Salida:** 10 neuronas (clases 0-9).
* **Formato de Datos:** Punto Fijo (Fixed Point) de 8 bits con signo.
* **Factor de Escala:** 128 (1.0 float ≈ 128 entero).

## Requisitos Previos

* **Python 3.10 o superior** (Recomendado 3.11 para estabilidad con TensorFlow).
* **Git** (para clonar este repositorio).

## Instalación y Configuración

Sigue estos pasos para crear un entorno virtual aislado y evitar conflictos de dependencias.

### 1. Clonar el repositorio

    git clone https://github.com/AlfonsoZen/ProyectoFPGA.git
    cd ProyectoFPGA

### 2. Crear el Entorno Virtual

**En Windows:**

    python -m venv venv
    .\venv\Scripts\activate

**En Linux / macOS:**

    python3 -m venv venv
    source venv/bin/activate

### 3. Instalar Dependencias
Una vez activo el entorno (verás `(venv)` en tu terminal), instala las librerías necesarias:

    pip install tensorflow numpy

*(Nota: TensorFlow puede tardar unos minutos en descargarse).*

## Ejecución

Para entrenar la red y generar los archivos de memoria, ejecuta el script principal:

    python entrenar.py

El proceso tomará unos segundos/minutos y verás el progreso del entrenamiento en la consola (Epoch 1/5...).

## Archivos Generados (Salida)

Al finalizar, el script generará 5 archivos `.mif` (Memory Initialization File) en la raíz del proyecto. Estos archivos son los que importaremos en **Quartus Prime**:

| Archivo | Descripción | Dimensiones |
| :--- | :--- | :--- |
| `rom_w1.mif` | Pesos de la Capa Oculta (Input -> Hidden) | 784x30 (Aplanado) |
| `rom_b1.mif` | Sesgos (Bias) de la Capa Oculta | 30 valores |
| `rom_w2.mif` | Pesos de la Capa de Salida (Hidden -> Output) | 30x10 (Aplanado) |
| `rom_b2.mif` | Sesgos (Bias) de la Capa de Salida | 10 valores |
| `img_prueba.mif` | Imagen del conjunto de test para validación | 784 valores |

## Detalles Técnicos sobre la Cuantización

La FPGA no maneja eficientemente números flotantes (ej. 0.345). Por ello, convertimos los pesos a enteros usando la fórmula:

    Valor_entero = Round(Valor_float * 128)

* Rango permitido (8 bits con signo): [-128, 127].
* Cualquier valor fuera de este rango es recortado (clipping).
* En VHDL, el resultado de las operaciones debe ser dividido por 128 (o shift right >> 7) para recuperar la escala original.

---
**Nota:** Si obtienes errores de versión con TensorFlow, asegúrate de estar usando un entorno virtual limpio y Python 3.10 o 3.11.