# EVO AI Lab

Documentación y configuración reproducible del laboratorio local de IA. El nodo **EVO-X3** es el plano de cómputo e inferencia; el **N150** existente es el plano de control del laboratorio. La integración completa entre ambos y algunos servicios de control siguen en evolución.

## Estado actual

- Hardware: GMKtec EVO-X3, AMD Ryzen AI Max+ 395 / Radeon 8060S (gfx1151), 128 GB instalados.
- Sistema observado: Ubuntu 24.04.4 LTS, kernel `7.0.0-30-generic`.
- Memoria Linux visible: ~124 GiB, con 1 GiB de VRAM fija y GTT dinámico de ~124 GiB.
- Runtime recomendado provisionalmente: `llama-vulkan-radv` en Distrobox.
- Modelo y perfil gestionado actuales: Qwen3.8-27B Q4_K_L con MTP, contexto 65 536 y `llama-server` en el puerto 8080.

El servicio expone una API compatible con OpenAI en `http://<EVO_IP>:8080/v1` dentro de la LAN. No debe exponerse directamente a Internet.

## Guía de lectura

- [Arquitectura](docs/architecture.md) y [hardware](docs/hardware.md)
- [Memoria UMA/GTT](docs/memory.md) y [monitorización](docs/monitoring.md)
- [Distrobox y backends](docs/distrobox.md)
- [Nodo de inferencia](docs/inference.md) y [red](docs/networking.md)
- [Benchmarks](docs/benchmarks.md), [diagnóstico](docs/troubleshooting.md) y [roadmap](docs/roadmap.md)

El perfil gestionado desplegado es [`qwen38-q4`](config/models/qwen38-q4.conf), operado por [`evo-model`](tools/model-manager/README.md) y su unidad genérica. `llama-qwen38.service` y su script siguen versionados como referencia del servicio anterior y posible rollback durante la estabilización. El repositorio nunca versiona modelos ni credenciales.

## Model manager v1 (implementado y desplegado)

[`evo-model`](tools/model-manager/README.md) está desplegado en el EVO-X3 para
seleccionar, cargar, detener y revisar un único modelo. El perfil inicial es
`qwen38-q4`, ejecutado con `llama-vulkan-radv` (RADV/Vulkan). Las capacidades
de múltiples modelos, control remoto, N150, LiteLLM, evo-top y descargas siguen
fuera de v1.

El catálogo de perfiles del repositorio cubre los GGUF inspeccionados en el
EVO-X3, incluidos modelos multimodales y Qwen Coder sharded; consultar
[config/models](config/models/README.md) para asociaciones y limitaciones.

La instalación o actualización user-local recomendada se realiza desde la raíz
del repositorio con `./install.sh`; no requiere `sudo` ni descarga pesos GGUF.
