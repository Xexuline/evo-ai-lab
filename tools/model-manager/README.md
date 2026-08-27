# `evo-model` v1 — implementado y desplegado

`evo-model` es un gestor local de **un único perfil activo** de `llama.cpp`.
Está desplegado en el EVO-X3 con el perfil inicial `qwen38-q4`. La migración
desde `llama-qwen38.service` se validó correctamente; la unidad anterior puede
conservarse temporalmente como mecanismo de rollback.

## Arquitectura

```text
evo-model start <perfil>
  -> valida config/models/<perfil>.conf y el modelo/contenedor
  -> guarda ~/.local/state/evo-model/selected-profile (modo 0600)
  -> systemctl --user start evo-model.service
  -> evo-model run-selected -> distrobox enter <container> -> llama-server
```

La unidad genérica `systemd/evo-model.service` ejecuta el perfil seleccionado;
no contiene nombres de modelos ni flags de Qwen. `run-selected` usa `exec` al
entrar en Distrobox, conservando la cadena de señales: al detener systemd, la
señal llega al proceso `distrobox` reemplazado y, por tanto, al `llama-server`
que ejecuta. Tiene `Type=simple`, `Restart=on-failure`, `RestartSec=5` y
`TimeoutStopSec=30`. Si no existe selección, sale con código 0 para evitar un
loop de reinicio intencional.

Los perfiles son datos declarativos con una lista cerrada de claves; no se usa
`source`. Véase [config/models](../../config/models/README.md). El estado solo
guarda el nombre seleccionado, no secretos. `stop` conserva esa selección;
`restart` la vuelve a usar. El servicio y la disponibilidad de API se consultan
en vivo con systemd y `GET /v1/models`, por lo que el estado no finge que un
proceso iniciado esté listo. El runtime efectivo lo determina `CONTAINER`:
`BACKEND` es solo metadata descriptiva. Por ejemplo, cambiar
`BACKEND=RADV/Vulkan` sin cambiar `CONTAINER=llama-vulkan-radv` no modifica el
backend que se ejecuta.

Los perfiles soportan tanto MTP integrado como un draft model externo. Un
perfil sin `DRAFT_MODEL_PATH` conserva el comportamiento de MTP integrado; si
declara `DRAFT_MODEL_PATH` y `DRAFT_GPU_LAYERS`, el runtime valida ambos y
añade `--spec-draft-model` y `--spec-draft-ngl` a `llama-server`. El perfil
`qwen36-mtp` para Qwen3.6 Q8_0 + MTP externo está implementado en el
repositorio y **pendiente de despliegue**.

## Uso

```bash
evo-model list
evo-model status
evo-model start qwen38-q4
evo-model stop
evo-model restart
evo-model logs
evo-model logs -f
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

`start` y `restart` validan el perfil, la ruta del GGUF y la existencia de la toolbox antes
de persistir la selección. Si el servicio *gestionado por evo-model* ya está
activo, lo detiene, comprueba con `ss` que el puerto del nuevo perfil haya
quedado libre y después inicia la nueva selección. Si otro proceso ocupa el
puerto, aborta sin matar procesos ni modificar servicios ajenos. No busca,
mata ni interfiere con otros `llama-server`. `restart` falla si no hay selección.

Tras `start` o `restart`, el comando espera hasta 180 segundos (configurable
para pruebas con `EVO_MODEL_HEALTH_TIMEOUT`) a que `http://127.0.0.1:<puerto>/v1/models`
responda correctamente, incluya la ruta completa del modelo o su nombre de
archivo, y `evo-model.service` continúe activo después de la respuesta. Si
systemd falla o vence el tiempo, devuelve error y recomienda `evo-model logs`.
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

## Despliegue y migración realizados

La instalación activa usa:

```text
~/.local/bin/evo-model
~/.local/share/evo-model/models/*.conf
~/.config/systemd/user/evo-model.service
~/.local/state/evo-model/selected-profile
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

## Límites de v1 y siguiente fase

No hay múltiples modelos residentes, API HTTP de control, daemon, descargas,
LiteLLM, N150, evo-top ni interfaz gráfica. Una fase posterior puede añadir un
orquestador remoto y una cola de cambios, manteniendo los perfiles declarativos
y el control exclusivo de la unidad `evo-model.service`.

## Verificación local

```bash
bash -n scripts/evo-model tests/test-evo-model.sh
./tests/test-evo-model.sh
```
