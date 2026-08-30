# Nodo de inferencia

## Estado actual

`evo-model` administra dos instancias locales independientes: `worker` en el
puerto 8080 y `agent` en el 8081. Un PROFILE describe modelo/runtime; una
INSTANCE determina el servicio, estado y puerto efectivo. Ambas APIs de
llama-server siguen siendo OpenAI-compatible y se consumen directamente. El
N150 continuará como control plane; esta fase no implementa SSH ni control remoto.

Las unidades systemd de usuario gestionadas son `evo-model@worker.service` y
`evo-model@agent.service`. Cada una lee exclusivamente la selección de su
instancia y puede ejecutar un perfil distinto. El perfil inicial documentado,
[`qwen38-q4`](../config/models/qwen38-q4.conf), entra en
`llama-vulkan-radv` y arranca `llama-server` con estos parámetros cuando se
selecciona para una instancia:

- Modelo: Qwen3.8-27B Q4_K_L de Bartowski.
- Backend: Vulkan/RADV.
- Capas GPU: `-ngl 999`.
- Contexto: `65536`.
- Paralelismo de secuencias: `-np 1`.
- Speculative decoding: MTP, `--spec-type draft-mtp`, máximo 2 drafts y `p-min` 0.8.
- Escucha: `0.0.0.0:8080`.

El archivo GGUF no está incluido ni debe añadirse al repositorio.

Además del perfil inicial, el catálogo de `evo-model` contiene perfiles para
los GGUF disponibles en el nodo. Cada instancia carga como máximo **un** perfil;
`worker` y `agent` pueden cargar perfiles simultáneamente. Los perfiles multimodales usan un `mmproj` cuando su asociación está
confirmada; Qwen Coder Next se carga indicando el primer shard, con el resto
del conjunto resuelto por llama.cpp. El detalle del catálogo y los modelos
deliberadamente excluidos está en [config/models](../config/models/README.md).

`llama-qwen38.service` fue el servicio específico usado anteriormente para
cargar Qwen3.8 directamente. Sus copias versionadas se conservan como referencia
y posible rollback durante la estabilización; esta documentación no afirma que
haya sido eliminado. La unidad de usuario se encuentra deliberadamente
deshabilitada para evitar que cargue automáticamente Qwen3.8 al arrancar.

`evo-model@worker.service` y `evo-model@agent.service` son las unidades
gestionadas mediante `evo-model`. La carga y descarga de modelos debe
gestionarse exclusivamente mediante `evo-model`; no se deben modificar las
unidades systemd de forma manual.

## Operación con systemd de usuario

```bash
evo-model list
evo-model status
evo-model start worker worker-default
evo-model start agent qwen38-q4
evo-model stop worker
evo-model restart agent
evo-model logs agent -f
```

`start` selecciona y carga un perfil tras validarlo; `stop` conserva la
selección; `restart` vuelve a usarla; `status` no modifica el estado. El gestor
usa su propia unidad `evo-model@<instancia>.service` internamente. `loginctl enable-linger <usuario>` permite
que el systemd user manager arranque durante el boot y mantenga servicios de
usuario sin requerir una sesión gráfica ni interactiva. Por ello el servicio
puede continuar después de cerrar sesión. El EVO tiene `Linger=yes` observado.

Usamos systemd para que el proceso tenga ciclo de vida declarativo, reinicio ante fallo y logs centralizados. Usamos Distrobox como runtime para fijar el stack de inferencia sin instalarlo directamente en el host.

## Comprobación funcional

```bash
evo-model status
curl http://<EVO_IP>:8080/v1/models
```

Ejecutar la segunda llamada desde un cliente LAN comprueba tanto el proceso como la ruta de red. No incluir tokens en comandos ni logs.

## Advertencia de seguridad actual

El servicio escucha actualmente en `0.0.0.0:8080` y el acceso directo se utiliza dentro de la LAN. Este endpoint **no debe considerarse autenticado**. No debe exponerse directamente a Internet ni abrirse mediante port forwarding. El diseño futuro delegará el acceso controlado en el control plane/gateway; no se asume aquí ningún mecanismo de autenticación que todavía no se haya desplegado.

## Reproducción y reversión

La instalación activa coloca `evo-model`, los perfiles y la unidad en las rutas
documentadas por el [model manager](../tools/model-manager/README.md). Para un
rollback conceptual durante la estabilización, detener `evo-model` y arrancar
manualmente `llama-qwen38.service`; revisar antes el estado y el journal para
comprobar una parada limpia. Son operaciones administrativas conscientes, no
acciones ejecutadas por esta documentación.
