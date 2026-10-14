# Perfiles de modelos

`evo-model` consume un archivo `nombre.conf` por perfil. Son ficheros de datos
`KEY=VALUE`, no se ejecutan ni se cargan con `source`. El parser admite solo las
claves siguientes y rechaza claves repetidas, desconocidas o incompletas:

```text
PROFILE_NAME       # debe coincidir con el nombre del archivo
MODEL_PATH         # ruta absoluta al GGUF
BACKEND            # gufo o llama.cpp/ROCm/Vulkan/RADV/Vulkan
CONTAINER          # llama.cpp: contenedor por defecto para instancias por perfil
RUNTIME_CONTAINER  # opcional; sustituye el contenedor de la instancia
SERVER_PATH        # opcional; ruta absoluta del ejecutable dentro del contenedor
HIP_LAUNCH_BLOCKING # opcional; 0/1 → variable de entorno del servidor
CONTEXT_SIZE
GPU_LAYERS
PARALLEL_SLOTS
SPEC_TYPE          # opcional; se omite el flag si no hay speculative decoding
DRAFT_MODEL_PATH   # opcional; GGUF draft externo, ruta absoluta
DRAFT_GPU_LAYERS   # opcional; requiere DRAFT_MODEL_PATH
MMPROJ_PATH        # opcional; proyector multimodal, ruta absoluta
SPEC_DRAFT_ADAPTIVE # opcional; on añade --spec-draft-adaptive; off lo omite
SPEC_DRAFT_N_MIN    # opcional; entero no negativo, no mayor que N_MAX
SPEC_DRAFT_N_MAX   # obligatorio solo con SPEC_TYPE
SPEC_DRAFT_P_MIN   # opcional; si se omite, usa el valor del runtime
FLASH_ATTN         # opcional; on/off → -fa
BATCH_SIZE         # opcional; entero positivo → -b
UBATCH_SIZE        # opcional; entero positivo → -ub
CACHE_TYPE_K       # opcional → --cache-type-k
CACHE_TYPE_V       # opcional → --cache-type-v
LAZY_MODE          # opcional; on/off → --lazy-mode
JINJA              # opcional; on/off → --jinja/--no-jinja
REASONING          # opcional; on/off → --reasoning
REASONING_PRESERVE # opcional; on añade --reasoning-preserve; off lo omite
HOST
PORT               # puerto efectivo en el host para cualquier instancia/backend
GUFO_IMAGE         # Gufo: referencia local por tag o digest
CONTAINER_PORT     # Gufo: puerto dentro del contenedor
SESSIONS           # Gufo: sesiones; no equivale a PARALLEL_SLOTS de llama.cpp
```

El perfil se valida antes de iniciar: valores numéricos, host y puerto, ruta de
modelo y las claves obligatorias. Para llama.cpp, el contenedor efectivo se comprueba durante
`evo-model start` y `restart` mediante `distrobox list`. Gufo comprueba Podman
rootless y que la imagen esté disponible localmente. Si se define
`DRAFT_MODEL_PATH`, debe ser una ruta absoluta a un GGUF existente y puede ir
acompañado de `DRAFT_GPU_LAYERS`, un entero no negativo. Si se omite, no se
pasa `--spec-draft-ngl`. `DRAFT_MODEL_PATH` usa `--spec-draft-model`, alias de `-md`.
`MMPROJ_PATH`, cuando existe, también debe ser una ruta absoluta a un GGUF
existente y se pasa como `--mmproj`.

No incluir GGUF, tokens, credenciales ni argumentos arbitrarios de shell en
estos ficheros. Para añadir un flag soportado de llama.cpp se amplía de forma
explícita el esquema y la construcción de argumentos en `scripts/evo-model`.

Para pasar `HIP_LAUNCH_BLOCKING` al servidor, añadir `HIP_LAUNCH_BLOCKING=1`
al perfil correspondiente (`0` también es válido). El gestor la pasa mediante
`env` dentro del contenedor, antes del ejecutable. Si se omite, no añade ninguna
asignación de esta variable al comando. No es un flag de llama.cpp ni selecciona
el backend; la build y el contenedor deben ser compatibles con HIP.

Por defecto, `worker` usa `llama-vulkan-worker` y `agent` usa
`llama-vulkan-radv`. `RUNTIME_CONTAINER` permite elegir otro contenedor.
`BACKEND=gufo` selecciona Podman; los backends ROCm/Vulkan conservan Distrobox.
Las instancias con nombre de perfil usan `RUNTIME_CONTAINER`, o `CONTAINER` si
se omite. El puerto efectivo siempre es `PORT`, también para worker y agent.

Las claves nuevas no añaden argumentos si están ausentes. Los tipos de caché
admitidos son `f32`, `f16`, `bf16`, `q8_0`, `q4_0`, `q4_1`, `iq4_nl`, `q5_0`
y `q5_1`. La build debe soportar los flags y tipos seleccionados.

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
| `qwen35-9b-mtp-q4` | Qwen3.5 9B MTP Q4_K_M | 98304 | MTP integrado | No |
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

`qwen35-9b-mtp-q4` usa 2 slots, 99 capas GPU, Flash Attention, cachés
`q8_0`, Jinja, reasoning y `draft-mtp` con máximo 3 tokens, sin draft externo.
Selecciona el binario `/home/evo/strix-llama.cpp/build/bin/llama-server`
dentro del contenedor Distrobox `llama-vulkan-worker`.
Su `PORT=8082` se respeta también al usar worker o agent.
La validación del perfil no comprueba la compatibilidad de la build ni el
arranque del modelo.

`qwen38-flash` conserva el backend ROCm, el contenedor `llama-rocm-strix`
y `/usr/local/bin/llama-server` como fallback explícito. No se cambia ni se
selecciona automáticamente al fallar Gufo.

`qwen38-flash-gufo` usa Gufo 0.13.0, Q4_K_XL, MTP externo, contexto 131072 y
3 sesiones. `PORT=8082` es un valor inicial de prueba, editable; el puerto
interno se declara con `CONTAINER_PORT=8081`. `GUFO_IMAGE` está fijada al digest
inspeccionado localmente; admite tags y digests, sin descargar automáticamente.

Para Gufo son obligatorias `PROFILE_NAME`, `BACKEND`, `MODEL_PATH`,
`CONTEXT_SIZE`, `SESSIONS`, `HOST`, `PORT`, `GUFO_IMAGE` y `CONTAINER_PORT`.
`SPEC_TYPE=mtp` requiere `DRAFT_MODEL_PATH`; ambos se pueden omitir para no usar
speculative decoding. Las claves exclusivas de llama.cpp se rechazan en Gufo,
incluidas `GPU_LAYERS`, `PARALLEL_SLOTS`, `CONTAINER` y `RUNTIME_CONTAINER`.
El nombre del contenedor Gufo lo genera el gestor a partir de la instancia.
Las rutas con espacios están soportadas; las rutas Gufo con `:` se rechazan.

Véase [operación y pruebas de Gufo](../../docs/gufo.md).

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
