# Hardware y sistema base

## Estado observado el 2026-08-26

- Equipo: GMKtec EVO-X3.
- CPU/APU: AMD Ryzen AI Max+ 395 con Radeon 8060S.
- Topología: 16 núcleos, 32 hilos, un socket.
- GPU: AMDGPU, PCI `1002:1586`; Vulkan la identifica como `AMD Radeon 8060S Graphics (RADV GFX1151)`.
- RAM visible para Linux: 124 GiB; swap configurada: 8.0 GiB.
- Distribución: Ubuntu 24.04.4 LTS.
- Kernel: `7.0.0-30-generic`.

La cifra de 128 GB se refiere a la RAM física instalada. La memoria que muestra Linux depende de la reserva UMA definida por firmware, explicada en [memory.md](memory.md).

## Comprobación segura

```bash
uname -a
lscpu
free -h
lspci -nn | rg -i 'vga|display|3d'
```

Estos comandos son de lectura. Una diferencia respecto a las cifras anteriores puede indicar otro kernel, un cambio de firmware o presión de memoria; no demuestra por sí sola un fallo.

## Reproducción y reversión

El hardware no se reproduce desde el repositorio. Los cambios de BIOS o kernel son operaciones administrativas fuera de este proyecto y no se realizan desde aquí. Antes de cambiar firmware, guardar los valores actuales y comprobar la memoria resultante al arrancar.
