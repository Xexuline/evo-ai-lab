# Monitorización

## Qué observar

Con UMA dinámica, `nvtop` sigue siendo valioso para carga de GPU, clocks, temperatura y potencia. Su número de VRAM puede ser engañoso porque la VRAM fija es de ~1 GiB mientras las asignaciones de modelos grandes se realizan principalmente a través de GTT.

Por tanto, para memoria de modelos se priorizan `mem_info_gtt_used` y `mem_info_gtt_total`. VRAM y GTT comparten la RAM física en esta APU, así que también hay que mirar memoria general del host.

## Comandos seguros

```bash
for f in /sys/class/drm/card*/device/mem_info_vram_used \
         /sys/class/drm/card*/device/mem_info_vram_total \
         /sys/class/drm/card*/device/mem_info_gtt_used \
         /sys/class/drm/card*/device/mem_info_gtt_total; do
  [ -r "$f" ] && printf '%s=' "$f" && cat "$f"
done

free -h
cat /sys/module/ttm/parameters/pages_limit
nvtop
```

Los cuatro valores DRM están en bytes. Registrar el estado antes, durante y después de una carga ayuda a separar uso residual, pesos de modelo y caché. `free -h` ofrece la perspectiva de RAM del host y `pages_limit` confirma el límite TTM aplicado.

## Roadmap: `evo-top`

No se implementa todavía. La futura TUI consolidará carga GPU, temperatura, potencia, VRAM, GTT, RAM, modelo cargado, contexto, backend, MTP y las últimas métricas de prefill, decode y acceptance extraídas de journald. Debe tratar los datos ausentes como tales, no estimarlos ni ocultar la distinción VRAM/GTT.
