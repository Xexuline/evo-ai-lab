# Gufo en evo-model

Gufo se integra en el mismo gestor y unidad systemd que llama.cpp. El perfil
`qwen38-flash-gufo` declara el modelo Q4_K_XL sharded, MTP externo, contexto
131072 y tres sesiones. El directorio del modelo se monta de solo lectura en
`/models`, incluyendo todos los shards. Si el MTP vive en otro directorio,
se monta de solo lectura en `/mtp`.

## Imagen y runtime

`GUFO_IMAGE` acepta una referencia por tag o digest. El perfil incluido fija:

```text
ghcr.io/gufo-org/toolboxes/gufo-runtime@sha256:e03e006da8485314e2440acbce5167c4659ef853af64ed339337f29fe43bd3b4
```

Este digest se obtuvo de `podman image inspect` de la imagen local que tenía
el tag `latest` el 2026-10-14. Su etiqueta `org.opencontainers.image.version`
es `0.13.0` y su ID local es
`1ef2822d9cdf9dc42e4ded7e00f649d92f8da820e107ff1c7ef2fb626ff99628`.
No había un contenedor de la prueba anterior conservado para cotejar su ID;
la correspondencia con aquella ejecución se basa en esa imagen local.

El gestor usa `--pull=never`: no cambia ni descarga imágenes durante un start.
En otro equipo debe estar disponible esa referencia localmente. Requisitos:
Podman rootless, acceso a `/dev/kfd` y `/dev/dri`, soporte de `keep-groups`
en el runtime OCI, systemd de usuario, curl, python3, flock y ss.
`keep-id` usa el UID y GID primario del usuario que ejecuta el gestor, obtenidos
con `id -u` e `id -g`, también como IDs dentro del contenedor.

## Instalación y operación

Editar `config/models/qwen38-flash-gufo.conf` antes de instalar para escoger
el puerto de producción. `PORT=8082` conserva únicamente el valor de prueba;
no está fijado en el gestor. `CONTAINER_PORT=8081` es independiente.

```bash
./install.sh
evo-model start qwen38-flash-gufo
evo-model status qwen38-flash-gufo
evo-model logs qwen38-flash-gufo -f
evo-model restart qwen38-flash-gufo
evo-model stop qwen38-flash-gufo
```

También se puede ejecutar `evo-model start agent qwen38-flash-gufo` y luego
operar sobre `agent`. El argumento de stop/restart/status/logs es siempre una
instancia concreta, sin buscar perfiles en otras instancias. Esta regla es
idéntica para ROCm, Vulkan y Gufo. La forma abreviada `start <profile>` dejó
de seleccionar worker; usar `start worker <profile>` para conservar ese uso.
Todos los backends respetan ahora `PORT`, también en worker y agent.

`status` muestra backend, modelo, contexto, sesiones, contenedor, estado del
contenedor, servicio y health endpoint. La salida de texto omite `Parallel slots`
para Gufo. En JSON, Gufo añade `sessions` y
`container_state`; `parallel_slots` y `context_per_slot` son null: no se aplica
la división de contexto de llama.cpp a Gufo.

Ready requiere servicio activo, contenedor ejecutándose y respuesta HTTP
200 de `/v1/models` con JSON válido y `data` como lista que contenga al menos
un objeto con `object=model` e `id` de texto no vacío. El ID puede ser un
nombre descriptivo y no tiene que coincidir con la ruta ni el archivo GGUF. Ni un contenedor running
ni una página de error con el nombre del modelo bastan. Un timeout detiene y
limpia la instancia; aumentar `EVO_MODEL_HEALTH_TIMEOUT` si la carga real tarda
más de los 180 segundos predeterminados.

## Parada e identidad

Antes de crear un contenedor se persiste un token aleatorio por ejecución en
`~/.local/state/evo-model/<instance>/gufo-owner`. El contenedor recibe ese token
y la instancia como etiquetas. El cidfile es auxiliar: perderlo no impide la
limpieza. El nombre legible `evo-model-gufo-<instance>` no autoriza por sí solo
la eliminación; nunca se usa `--replace` ni se eliminan contenedores por nombre.

`ExecStopPost` descubre los IDs completos por ambas etiquetas, vuelve a
comprobar propiedad, elimina cada contenedor con plazo de 10 segundos y
comprueba su ausencia. El registro se conserva si hay errores. La limpieza es
idempotente y no carga el perfil, por lo que funciona tras perder el wrapper,
el modelo o el archivo de configuración. `stop` vuelve a verificarla aunque
la unidad ya estuviera inactiva. La implementación exige ausencia, una
condición más fuerte que simplemente no estar ejecutándose.

La unidad tiene `KillMode=control-group` y `TimeoutStopSec=45`; la fase de
limpieza posterior puede añadir los 10 segundos de parada de Podman.
La limpieza explícita es necesaria porque los procesos de un contenedor pueden
pertenecer a otro cgroup; terminar el cliente Podman no demuestra que hayan
terminado. Referencias: [podman run](https://docs.podman.io/en/latest/markdown/podman-run.1.html)
y [podman rm](https://docs.podman.io/en/latest/markdown/podman-rm.1.html).

La lógica nueva no garantiza una parada dentro de toolboxes Distrobox
compartidas de llama.cpp; ese runtime se mantiene compatible y no se elimina
su contenedor. No se hace fallback automático ni se usan comandos pkill.

## Fallback ROCm

El perfil `qwen38-flash` permanece sin cambios. Para cambiar explícitamente:

```bash
evo-model stop qwen38-flash-gufo
evo-model start agent qwen38-flash
```

Si Gufo se inició en `agent`, usar `evo-model stop agent` primero. Revisar el
puerto del perfil ROCm y no cargar ambos modelos si no hay memoria suficiente.

## Validación

```bash
bash tests/test-evo-model.sh
python3 tests/test-evo-model-gufo.py
bash tests/test-install.sh
bash tests/test-evo-model-remote.sh
```

Prueba opcional con Podman y systemd reales, usando solo shell/sleep dentro de
un contenedor temporal sin GPU ni modelos:

```bash
EVO_MODEL_INTEGRATION_IMAGE=ghcr.io/gufo-org/toolboxes/gufo-runtime@sha256:e03e006da8485314e2440acbce5167c4659ef853af64ed339337f29fe43bd3b4 \
  bash tests/test-evo-model-gufo-integration.sh
```

Verifica parada normal, muerte por SIGKILL del cliente Podman, eliminación por
ExecStopPost y limpieza repetida. No sustituye una prueba de carga del modelo
con la configuración final de producción.
