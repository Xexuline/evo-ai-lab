# Nodo de inferencia

## Estado actual

El servicio activo es una unidad systemd de usuario llamada `llama-qwen38.service`, habilitada y en ejecución durante la inspección. Ejecuta [el script versionado](../scripts/llama-qwen38.sh), que entra en `llama-vulkan-radv` y arranca `llama-server` con este perfil:

- Modelo: Qwen3.8-27B Q4_K_L de Bartowski.
- Backend: Vulkan/RADV.
- Capas GPU: `-ngl 999`.
- Contexto: `65536`.
- Paralelismo de secuencias: `-np 1`.
- Speculative decoding: MTP, `--spec-type draft-mtp`, máximo 2 drafts y `p-min` 0.8.
- Escucha: `0.0.0.0:8080`.

La copia del script conserva el path real del modelo para reflejar el perfil activo. El archivo GGUF no está incluido ni debe añadirse al repositorio.

## Operación con systemd de usuario

```bash
systemctl --user start llama-qwen38.service    # inicia si está parado
systemctl --user enable llama-qwen38.service   # habilita inicio con el user manager
systemctl --user restart llama-qwen38.service  # reinicia tras cambiar el perfil
systemctl --user status llama-qwen38.service   # estado, PID y últimos logs
journalctl --user -u llama-qwen38.service -f   # sigue el journal en directo
```

`start` solo cambia el estado actual; `enable` crea la relación de arranque y no equivale a iniciar inmediatamente; `restart` detiene y vuelve a crear el proceso; `status` no modifica nada. `loginctl enable-linger <usuario>` permite que el systemd user manager arranque durante el boot y mantenga servicios de usuario sin requerir una sesión gráfica ni interactiva. Por ello el servicio puede continuar después de cerrar sesión. El EVO tiene `Linger=yes` observado.

Usamos systemd para que el proceso tenga ciclo de vida declarativo, reinicio ante fallo y logs centralizados. Usamos Distrobox como runtime para fijar el stack de inferencia sin instalarlo directamente en el host.

## Comprobación funcional

```bash
systemctl --user is-active llama-qwen38.service
curl http://<EVO_IP>:8080/v1/models
```

Ejecutar la segunda llamada desde un cliente LAN comprueba tanto el proceso como la ruta de red. No incluir tokens en comandos ni logs.

## Advertencia de seguridad actual

El servicio escucha actualmente en `0.0.0.0:8080` y el acceso directo se utiliza dentro de la LAN. Este endpoint **no debe considerarse autenticado**. No debe exponerse directamente a Internet ni abrirse mediante port forwarding. El diseño futuro delegará el acceso controlado en el control plane/gateway; no se asume aquí ningún mecanismo de autenticación que todavía no se haya desplegado.

## Reproducción y reversión

Copiar los archivos de este repositorio a sus rutas de usuario, instalar el modelo en el path referenciado (o ajustar el perfil), y recargar/habilitar la unidad son operaciones administrativas que deben hacerse conscientemente, no mediante esta documentación. Para revertir un perfil, restaurar el script y unidad previos y reiniciar la unidad. Antes, revisar `status` y el journal para comprobar una parada limpia.
