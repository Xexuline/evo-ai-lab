# Perfiles de modelos

`evo-model` consume un archivo `nombre.conf` por perfil. Son ficheros de datos
`KEY=VALUE`, no se ejecutan ni se cargan con `source`. El parser admite solo las
claves siguientes y rechaza claves repetidas, desconocidas o incompletas:

```text
PROFILE_NAME       # debe coincidir con el nombre del archivo
MODEL_PATH         # ruta absoluta al GGUF
BACKEND            # metadata descriptiva; no selecciona el runtime
CONTAINER          # nombre de la toolbox Distrobox que determina el runtime
CONTEXT_SIZE
GPU_LAYERS
PARALLEL_SLOTS
SPEC_TYPE
SPEC_DRAFT_N_MAX
SPEC_DRAFT_P_MIN
HOST
PORT
```

El perfil se valida antes de iniciar: valores numéricos, host y puerto, ruta de
modelo y las claves obligatorias. `CONTAINER` se comprueba además durante
`evo-model start` y `restart` mediante `distrobox list`.

No incluir GGUF, tokens, credenciales ni argumentos arbitrarios de shell en
estos ficheros. Para añadir un flag soportado de llama.cpp se amplía de forma
explícita el esquema y la construcción de argumentos en `scripts/evo-model`.

Por ejemplo, `BACKEND=RADV/Vulkan` junto con
`CONTAINER=llama-vulkan-radv` documenta la elección. Cambiar solamente
`BACKEND` no cambia qué toolbox ni backend se ejecuta.

`qwen38-q4.conf` replica el servidor Qwen3.8 actual, pero no sustituye el
servicio operativo existente: esta versión está implementada en el repositorio
y pendiente de despliegue.
