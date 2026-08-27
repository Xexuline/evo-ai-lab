# Distrobox y backends de inferencia

## Estado observado

`distrobox` está en la versión `1.8.2.5`. Se observaron estas toolboxes:

| Nombre | Imagen | Estado observado |
| --- | --- | --- |
| `llama-vulkan-radv` | `docker.io/kyuz0/amd-strix-halo-toolboxes:vulkan-radv` | En ejecución |
| `llama-rocm` | `docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-7.14` | Detenida (salida 143) |

La instalación actual de `llama-vulkan-radv` informó `llama.cpp` build **10612**, commit `758443071`. La referencia histórica a build 10630 describe una build observada anteriormente, no la instalada durante esta inspección.

## Decisión provisional: RADV

RADV/Vulkan es el backend recomendado actualmente por estabilidad y rendimiento observados. Se ha usado con éxito con Qwen3.8, Qwen3.6, GPT-OSS y Qwen Coder Next. La toolbox detecta la Radeon 8060S como RADV GFX1151 y anuncia 128000 MiB direccionables.

ROCm 7.14 está disponible para reevaluación. La actualización de Distrobox corrigió el problema de versiones antiguas que fallaban al configurar usuarios en imágenes Fedora recientes. ROCm 7.14 ya funciona con Qwen3.8 + MTP, pero no desplaza todavía la recomendación de RADV. Esta conclusión es temporal: comparar de nuevo tras actualizar driver, imagen, ROCm o llama.cpp.

## Por qué Distrobox

Distrobox encapsula las dependencias de runtime (Vulkan/RADV o ROCm, binarios y librerías) sin convertir la instalación base de Ubuntu en el lugar donde se mantiene cada stack de inferencia. El script de servicio entra explícitamente en la toolbox elegida, por lo que el backend forma parte del perfil reproducible.

## Comprobación segura

```bash
distrobox --version
distrobox list
distrobox enter llama-vulkan-radv -- llama-cli --version
distrobox enter llama-vulkan-radv -- llama-cli --list-devices
```

El último comando debe listar la Radeon 8060S. Consultar una toolbox detenida no obliga a arrancarla; evitar hacerlo únicamente para diagnóstico si se desea preservar su estado.

## Reproducción y reversión

Crear o actualizar toolboxes modifica el sistema de contenedores y queda fuera de esta tarea. Para reproducir, conservar los nombres e imágenes de la tabla, validar GPU y versión de `llama.cpp`, y probar un modelo conocido antes de ponerlo como servicio. Para revertir una actualización, volver a una imagen previamente validada; documentar su digest antes de sustituirla.
