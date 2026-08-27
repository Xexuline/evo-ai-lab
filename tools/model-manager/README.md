# `evo-model` v1 — implementado en repositorio, pendiente de despliegue

`evo-model` es un gestor local de **un único perfil activo** de `llama.cpp`.
No desplaza ni controla el actual `llama-qwen38.service`; la migración será una
operación manual y controlada posterior.

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

## Futuro despliegue y migración

No se ha instalado ni iniciado nada en esta fase. La disposición prevista es:

```text
~/.local/bin/evo-model
~/.local/share/evo-model/config/models/*.conf
~/.config/systemd/user/evo-model.service
~/.local/state/evo-model/selected-profile
```

El gestor instalado detecta preferentemente
`$XDG_DATA_HOME/evo-model/config/models` (por defecto
`~/.local/share/evo-model/config/models`); al ejecutarse desde el repositorio
usa `config/models`. Antes de migrar hay que revisar el puerto 8080 y parar
manualmente el servicio antiguo en una ventana de mantenimiento. Rollback:
detener solo `evo-model.service` y volver a iniciar la unidad anterior; no se
borra ningún modelo ni su selección. No habilitar la nueva unidad hasta haber
comprobado ese cambio.

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
