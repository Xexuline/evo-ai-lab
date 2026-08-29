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
SPEC_TYPE          # opcional; se omite el flag si no hay speculative decoding
DRAFT_MODEL_PATH   # opcional; GGUF draft externo, ruta absoluta
DRAFT_GPU_LAYERS   # obligatorio junto con DRAFT_MODEL_PATH
MMPROJ_PATH        # opcional; proyector multimodal, ruta absoluta
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
`MMPROJ_PATH`, cuando existe, también debe ser una ruta absoluta a un GGUF
existente y se pasa como `--mmproj`.

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
separado y declara ambas claves. Está implementado y desplegado.

## Catálogo inspeccionado

Los siguientes perfiles corresponden a GGUF presentes en `/home/evo/models`.
El contexto es una elección inicial conservadora por perfil, no una promesa de
rendimiento ni un benchmark.

| Perfil | Modelo principal | Contexto | Speculative | Multimodal |
| --- | --- | ---: | --- | --- |
| `qwen38-q4` | Qwen3.8 27B Q4_K_L | 65536 | MTP integrado | No |
| `qwen36-mtp` | Qwen3.6 35B-A3B Q8_0 | 65536 | Draft MTP externo | Sí |
| `qwen36-abliterated-vl` | Qwen3.6 Heretic Q8_0 | 32768 | No | Sí |
| `qwen35-q8-vl` | Qwen3.5 35B-A3B Q8_0 | 32768 | No | Sí |
| `qwen38-abliterated-mtp-vl` | Qwen3.8 Aggressive Q8_K_P | 32768 | MTP integrado | Sí |
| `gpt-oss-120b` | GPT-OSS 120B MXFP4 | 16384 | No | No |
| `coder-next-q5` | Qwen Coder Next Q5_K_M | 32768 | No | No |
| `worker-default` | Qwen3.6 35B-A3B Q8_0 | 65536 | Draft MTP externo | No |
| `worker-dedicated` | Qwen3.6 35B-A3B Q8_0 | 131072 | Draft MTP externo | No |
| `worker-fast` | Qwen3.6 35B-A3B Q4_K_M | 65536 | Draft MTP externo | No |

`coder-next-q5` apunta al shard `00001-of-00004`: llama.cpp carga el conjunto
completo a partir de ese primer archivo, por lo que no se crean perfiles por
shard. Los `mmproj` y drafts tampoco son perfiles independientes; se asocian
solo cuando la relación es clara.

Qwen3.8 Flash no forma parte del catálogo estable. Su conjunto de tres shards
(UD-IQ4_XS) ya está completo, incluido `00002`, pero se está probando con una
build experimental/específica de llama.cpp (`llama-vulkan-test`) y todavía no se
integra en `evo-model`. Esperamos a disponer de un runtime suficientemente
estable, especialmente con soporte MTP funcional.

El sidecar Eagle3 de GPT-OSS y el FastMTP de la variante Qwen3.8 Aggressive no
se activan: su configuración/runtime compatible no está confirmada para esta
instalación. El último requiere además un parche de llama.cpp según el README
local.

Los perfiles `worker-*` están orientados a uso como workers (inferencia programática
mediante API). Comparten el mismo modelo base que `qwen36-mtp` pero difieren en
contexto y slots paralelos: `worker-default` usa 2 slots para mayor concurrencia,
`worker-dedicated` usa 131072 de contexto para cargas largas de un único agente, y
`worker-fast` usa una versión Q4_K_M (menor precisión) para menor latencia. Ninguno
incluye `MMPROJ_PATH` por lo que no se usan con capacidades multimodales.

`worker-dedicated` está optimizado para cargas largas de un único agente con
131072 de contexto.
