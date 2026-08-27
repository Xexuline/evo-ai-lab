# Memoria UMA, VRAM y GTT

## Estado actual observado

La BIOS se configuró previamente con `iGPU Configuration = UMA_SPECIFIED` y `UMA Frame Buffer Size = 1G`. Linux ve aproximadamente 124 GiB y AMDGPU informa 1 GiB de VRAM fija.

El GRUB instalado contiene:

```text
amdgpu.gttsize=126976 ttm.pages_limit=32505856
```

La línea de arranque activa contiene los mismos parámetros. En esta observación, DRM informó 1 073 741 824 bytes de VRAM total y 133 143 986 176 bytes de GTT total (aprox. 124 GiB). Vulkan/RADV anunció 128000 MiB direccionables.

## Qué hace y por qué

La VRAM fija es la porción de RAM que el firmware aparta desde el arranque para la iGPU. GTT (Graphics Translation Table), gestionada por TTM, permite que el driver mapee más RAM del sistema para recursos gráficos y de cómputo. Con UMA, ambas provienen de la misma memoria física.

Antes, una reserva fija de ~64 GB dejaba a Linux cerca de 62 GiB. La reserva fija de 1 GiB más GTT dinámico conserva RAM utilizable por el sistema y permite a `llama.cpp` usar grandes asignaciones de GPU bajo demanda. Es la decisión actual porque beneficia modelos grandes sin inmovilizar 64 GB desde firmware.

`nvtop` puede mostrar solo ~1 GB de VRAM aunque un modelo use mucha más memoria: normalmente refleja la VRAM fija, no todo el espacio GTT asignado. Para esta APU, GTT es la métrica principal de memoria de modelos.

## Verificación segura

```bash
cat /proc/cmdline
rg '^GRUB_CMDLINE_LINUX' /etc/default/grub
cat /sys/module/ttm/parameters/pages_limit

for f in /sys/class/drm/card*/device/mem_info_{vram,gtt}_{used,total}; do
  [ -r "$f" ] && printf '%s=' "$f" && cat "$f"
done

free -h
```

Los valores de DRM están en bytes. `mem_info_gtt_used` aumenta con las asignaciones dinámicas; compararlo con `mem_info_gtt_total`, no con la VRAM fija aislada.

## Reproducción y reversión (operación manual)

Reproducir esta estrategia requiere cambiar la BIOS a los dos valores anteriores y añadir los parámetros observados a `GRUB_CMDLINE_LINUX_DEFAULT` en `/etc/default/grub`, regenerar la configuración de GRUB y reiniciar. Es una operación de sistema: **no se ejecuta desde este repositorio**. Para revertir, restaurar los valores de BIOS y GRUB previamente anotados, regenerar GRUB y reiniciar. Validar siempre con `/proc/cmdline`, `pages_limit` y `free -h` tras el arranque.
