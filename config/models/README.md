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
DRAFT_MODEL_PATH   # opcional; GGUF draft externo, ruta absoluta
DRAFT_GPU_LAYERS   # obligatorio junto con DRAFT_MODEL_PATH
SPEC_DRAFT_N_MAX
SPEC_DRAFT_P_MIN
HOST
PORT
```

El perfil se valida antes de iniciar: valores numéricos, host y puerto, ruta de
modelo y las claves obligatorias. `CONTAINER` se comprueba además durante
`evo-model start` y `restart` mediante `distrobox list`. Si se define
`DRAFT_MODEL_PATH`, debe ser una ruta absoluta a un GGUF existente y debe ir
acompañado de `DRAFT_GPU_LAYERS`, un entero no negativo.

No incluir GGUF, tokens, credenciales ni argumentos arbitrarios de shell en
estos ficheros. Para añadir un flag soportado de llama.cpp se amplía de forma
explícita el esquema y la construcción de argumentos en `scripts/evo-model`.

Por ejemplo, `BACKEND=RADV/Vulkan` junto con
`CONTAINER=llama-vulkan-radv` documenta la elección. Cambiar solamente
`BACKEND` no cambia qué toolbox ni backend se ejecuta.

`qwen38-q4.conf` es el perfil inicial desplegado de EVO-X3: reproduce Qwen3.8
Q4_K_L con RADV/Vulkan, MTP, contexto 65 536 y escucha en `0.0.0.0:8080`.
El servicio anterior `llama-qwen38.service` se conserva documentado como
referencia y posible rollback durante la estabilización.

Qwen3.8 usa MTP integrado: no define `DRAFT_MODEL_PATH`, por lo que no se
añaden flags de draft externo. `qwen36-mtp.conf` usa MTP con un GGUF draft
separado y declara ambas claves. Está implementado en el repositorio y
**pendiente de despliegue**.
