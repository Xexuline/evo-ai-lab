# `evo-model` — instancias locales de inferencia

`evo-model` administra instancias locales de llama.cpp (Distrobox, ROCm/Vulkan)
y Gufo (Podman rootless). Un **profile** configura modelo/backend; una
**instance** identifica un servicio, selección, lock y ejecución concreta.
`worker` y `agent` siguen disponibles. `start <profile>` crea una instancia
con ese mismo nombre para cualquier backend; no es un alias de worker.
`PORT` del perfil determina siempre el puerto efectivo.

## Arquitectura

```text
evo-model start worker <perfil>
  -> valida config/models/<perfil>.conf y el modelo/contenedor
  -> guarda ~/.local/state/evo-model/worker/selected-profile (modo 0600)
  -> systemctl --user start evo-model@worker.service
  -> evo-model run-selected worker -> distrobox enter <container> -> llama-server
```

La plantilla `systemd/evo-model@.service` ejecuta el perfil seleccionado con
`run-selected <instance>`. El despacho por `BACKEND` construye los argumentos
de llama.cpp o Gufo dentro del mismo gestor. La unidad usa `Type=simple`,
`Restart=on-failure`, `RestartSec=5`, `KillMode=control-group` y
`TimeoutStopSec=45`. `ExecStopPost` llama a `cleanup-runtime`, también si muere
el proceso principal o falla el arranque.

Gufo registra un token antes de crear el contenedor. La limpieza descubre IDs
completos por ese token y la instancia, verifica ambas etiquetas y elimina
exclusivamente esos IDs, con parada limitada a 10 segundos y escalado a kill.
Confirma la ausencia antes de eliminar el registro de propiedad. No depende
del perfil ni del cidfile; conserva el registro ante errores para poder
reintentar. `stop` verifica la limpieza incluso cuando la unidad ya estaba
inactiva. Un error de inspección no se interpreta como ausencia.

La ejecución histórica mediante `exec distrobox enter` se conserva para
llama.cpp. Por sí sola no garantiza que un proceso dentro de un contenedor
externo reciba las señales de systemd; la limpieza por identidad descrita arriba
es para los contenedores Gufo creados por el gestor. No se detienen toolboxes
compartidas ni se matan procesos llama-server por nombre.

Los perfiles son datos declarativos; no se usa `source`. Véase
[config/models](../../config/models/README.md). `stop` retiene la selección y
`restart` la reutiliza. Para llama.cpp, worker usa `llama-vulkan-worker` y
agent usa `llama-vulkan-radv`, salvo `RUNTIME_CONTAINER`. Otras instancias
usan `RUNTIME_CONTAINER` o `CONTAINER` del perfil. Gufo siempre crea su propio
contenedor con nombre `evo-model-gufo-<instance>` y etiquetas por ejecución.

Los perfiles soportan tanto MTP integrado como un draft model externo. Un
perfil sin `DRAFT_MODEL_PATH` conserva el comportamiento de MTP integrado; si
declara `DRAFT_MODEL_PATH` y `DRAFT_GPU_LAYERS`, el runtime valida ambos y
añade `--spec-draft-model` y `--spec-draft-ngl` a `llama-server`. El perfil
`qwen36-mtp` para Qwen3.6 Q8_0 + MTP externo está implementado y desplegado.

Los perfiles multimodales pueden declarar `MMPROJ_PATH`; el gestor valida el
GGUF del proyector y añade `--mmproj`. Los modelos sharded se representan por
el primer shard: llama.cpp carga el resto del conjunto automáticamente. Véase
el [catálogo de perfiles](../../config/models/README.md#catálogo-inspeccionado).

## Uso

```bash
evo-model list
evo-model status
evo-model start worker worker-default
evo-model start agent qwen38-q4
evo-model stop agent
evo-model restart worker
evo-model logs agent -f
evo-model start qwen38-flash-gufo
evo-model status qwen38-flash-gufo
evo-model stop qwen38-flash-gufo
```

## Autocompletado Bash

El completion incluido propone los comandos de `evo-model`, consulta los
perfiles dinámicamente con `evo-model list` al completar `evo-model start` y
ofrece `-f` y `--follow` para `logs`. No inicia, detiene ni modifica servicios.

Para instalarlo para el usuario:

```bash
install -Dm644 completions/evo-model.bash \
  ~/.local/share/bash-completion/completions/evo-model
```

Abrir una nueva shell Bash o cargar el archivo con `source` para activarlo en
la sesión actual. Si `evo-model list` falla, el completion no sugiere perfiles.

`start` y `restart` validan el perfil, el GGUF y el runtime antes
de persistir la selección. Si el servicio *gestionado por evo-model* ya está
activo, lo detiene, comprueba con `ss` que el puerto del nuevo perfil haya
quedado libre y después inicia la nueva selección. Si otro proceso ocupa el
puerto, aborta sin matar procesos ni modificar servicios ajenos. No busca,
mata ni interfiere con otros `llama-server`. `restart` falla si no hay selección.

Tras `start` o `restart`, el comando espera hasta 180 segundos (configurable
para pruebas con `EVO_MODEL_HEALTH_TIMEOUT`) a que `http://127.0.0.1:<puerto>/v1/models`
responda correctamente y la unidad de la instancia continúe activa después
de la respuesta. Para llama.cpp se sigue exigiendo la ruta completa del modelo
o su nombre de archivo. Para Gufo no se compara el nombre: se exige HTTP 200,
JSON válido y `data`
como lista con al menos un objeto `object=model` e `id` de texto no vacío,
además de confirmar que el contenedor esté ejecutándose. Si systemd falla o
vence el tiempo, se detiene la instancia, se limpia Gufo y se devuelve error.
Durante la espera muestra un contador por cada polling y, al quedar lista la
API, el tiempo operativo total desde que solicitó el arranque. No es un
benchmark de inferencia.
Sin autenticación entre procesos, dos servidores diferentes que sirvan
exactamente el mismo `MODEL_PATH` en el mismo puerto no pueden distinguirse
solo mediante `/v1/models`; la migración requiere detener primero
`llama-qwen38.service` para eliminar ese conflicto.

La comprobación de puerto reduce conflictos antes del arranque, pero no elimina
la carrera normal entre comprobarlo e iniciar el servicio: otro proceso podría
ocuparlo entre ambas operaciones. En ese caso systemd fallará al iniciar y el
gestor remitirá a los logs.

En Distrobox 1.8.2.5, `distrobox list` no ofrece salida machine-readable. El
gestor usa `--no-color` y analiza la columna `NAME` de la tabla `ID | NAME |
STATUS | IMAGE`, comparando el nombre completo, no prefijos parciales.

El uso de `0.0.0.0:8080` en el perfil inicial es exclusivamente para la LAN de
confianza. La API no está autenticada: no exponerla a Internet ni usar port
forwarding.

## Instalación y actualización

La vía recomendada, tanto para la primera instalación como para actualizar una
existente, es ejecutar desde la raíz del repositorio:

```bash
./install.sh
```

No requiere `sudo`, no descarga ni copia GGUF y no inicia, detiene, reinicia,
habilita o deshabilita servicios. Instala o actualiza la CLI, la unidad, el
completion Bash y todos los perfiles `config/models/*.conf`. El directorio
`~/.local/share/evo-model/models` es gestionado por `install.sh`: antes de
copiar elimina únicamente los archivos `*.conf` de ese directorio para que el
repositorio sea la fuente de verdad. No colocar ahí perfiles locales manuales,
porque desaparecerán en la siguiente instalación; los archivos que no son
`.conf` no se eliminan. Tras copiar la unidad ejecuta únicamente
`systemctl --user daemon-reload`. Una shell Bash que ya estuviera abierta puede
recargar el completion con:

```bash
source ~/.local/share/bash-completion/completions/evo-model
```

## Despliegue y migración realizados

La instalación activa usa:

```text
~/.local/bin/evo-model
~/.local/share/evo-model/models/*.conf
~/.config/systemd/user/evo-model@.service
~/.local/state/evo-model/<instance>/selected-profile
```

La resolución de perfiles, en orden, es: `EVO_MODEL_PROFILE_DIR` si está
definida; `$HOME/.local/share/evo-model/models` si existe; y `config/models`
relativo al repositorio durante desarrollo. La ubicación instalada ignora
deliberadamente `XDG_DATA_HOME`: `evo-model` es una herramienta administrativa
del usuario y debe ver los mismos perfiles desde terminal, SSH, systemd de
usuario y terminales sandboxed como VS Code/Snap. Si ninguna carpeta existe,
se conserva la ruta instalada esperada para que `evo-model --help` siga
funcionando; los comandos que necesitan un perfil indicarán que no se
encuentra. El estado usa
`$XDG_STATE_HOME/evo-model` o `~/.local/state/evo-model` como fallback.

La migración validada instaló esos tres componentes, recargó el user manager,
validó perfil y runtime, comprobó el puerto 8080 y detuvo el servicio anterior
antes de ejecutar `evo-model start qwen38-q4`. El health check confirmó de nuevo
la API. La protección de puerto también se verificó: mientras
`llama-qwen38.service` ocupaba 8080, `evo-model` se negó a arrancar.

Rollback conceptual durante la estabilización:

```bash
evo-model stop
systemctl --user start llama-qwen38.service
```

No elimina perfiles ni modelos. Ejecutar el rollback es una operación
administrativa deliberada; no se hace automáticamente.

## Entorno administrativo

Usar una terminal normal del sistema, SSH o systemd para administrar
`evo-model` y diagnosticar Distrobox. En el terminal integrado de VS Code
instalado mediante Snap se observó un entorno diferente: puede alterar variables
como `XDG_DATA_HOME` y la detección de Distrobox. No se trata como un bug
confirmado de VS Code o Distrobox, sino como una diferencia observada en ese
entorno; consultar [troubleshooting](../../docs/troubleshooting.md).

## Compatibilidad de CLI y puertos

`start worker <profile>` y `start agent <profile>` mantienen sus selecciones y
unidades. **Cambio deliberado:** `start <profile>` ahora crea la instancia
`<profile>`; para el comportamiento anterior usar `start worker <profile>`.
`stop/restart/status/logs <nombre>` siempre direccionan esa instancia exacta;
no buscan en qué otra instancia está seleccionado un perfil. Sin argumento,
stop/restart/logs siguen usando worker; status enumera worker, agent y las
instancias creadas. `status --json` conserva la raíz `instances`.

**Cambio de puertos:** se respeta `PORT` en todos los casos. Revisarlo antes de
actualizar, especialmente si se reutiliza un perfil en worker y agent: dos
instancias no pueden ocupar el mismo puerto. Las instancias genéricas de
llama.cpp pueden compartir toolbox; esto no implica aislamiento del contenedor.
El wrapper SSH restringido conserva su allowlist actual de worker/agent.

La instalación no inicia servicios ni carga modelos. Para Gufo, ver
[imagen, configuración, fallback y pruebas](../../docs/gufo.md).

## Verificación local

```bash
bash -n scripts/evo-model tests/test-evo-model.sh
./tests/test-evo-model.sh
python3 tests/test-evo-model-gufo.py
bash tests/test-install.sh
bash tests/test-evo-model-remote.sh
```
