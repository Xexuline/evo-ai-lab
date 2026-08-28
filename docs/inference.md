# Nodo de inferencia

## Estado actual

El servicio gestionado activo es la unidad systemd de usuario
`evo-model.service`, seleccionada mediante `evo-model`. El perfil inicial
desplegado es [`qwen38-q4`](../config/models/qwen38-q4.conf), que entra en
`llama-vulkan-radv` y arranca `llama-server` con este perfil:

- Modelo: Qwen3.8-27B Q4_K_L de Bartowski.
- Backend: Vulkan/RADV.
- Capas GPU: `-ngl 999`.
- Contexto: `65536`.
- Paralelismo de secuencias: `-np 1`.
- Speculative decoding: MTP, `--spec-type draft-mtp`, máximo 2 drafts y `p-min` 0.8.
- Escucha: `0.0.0.0:8080`.

El archivo GGUF no está incluido ni debe añadirse al repositorio.

Además del perfil inicial, el catálogo de `evo-model` contiene perfiles para
los GGUF disponibles en el nodo. El gestor sigue cargando solo **un** perfil a
la vez. Los perfiles multimodales usan un `mmproj` cuando su asociación está
confirmada; Qwen Coder Next se carga indicando el primer shard, con el resto
del conjunto resuelto por llama.cpp. El detalle del catálogo y los modelos
deliberadamente excluidos está en [config/models](../config/models/README.md).

`llama-qwen38.service` fue el servicio específico usado anteriormente para
cargar Qwen3.8 directamente. Sus copias versionadas se conservan como referencia
y posible rollback durante la estabilización; esta documentación no afirma que
haya sido eliminado. La unidad de usuario se encuentra deliberadamente
deshabilitada para evitar que cargue automáticamente Qwen3.8 al arrancar.

`evo-model.service` es ahora el servicio gestionado mediante `evo-model`. A
diferencia del servicio anterior, puede estar habilitado al inicio. La carga y
descarga de modelos debe gestionarse exclusivamente mediante `evo-model`; no se
deben modificar las unidades systemd de forma manual.

## Operación con systemd de usuario

```bash
evo-model list
evo-model status
evo-model start qwen38-q4
evo-model stop
evo-model restart
evo-model logs -f
```

`start` selecciona y carga un perfil tras validarlo; `stop` conserva la
selección; `restart` vuelve a usarla; `status` no modifica el estado. El gestor
usa `evo-model.service` internamente. `loginctl enable-linger <usuario>` permite
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
