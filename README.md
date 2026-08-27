# EVO AI Lab

Documentación y configuración reproducible del laboratorio local de IA. El nodo **EVO-X3** es el plano de cómputo e inferencia; el **N150** existente es el plano de control del laboratorio. La integración completa entre ambos y algunos servicios de control siguen en evolución.

## Estado actual

- Hardware: GMKtec EVO-X3, AMD Ryzen AI Max+ 395 / Radeon 8060S (gfx1151), 128 GB instalados.
- Sistema observado: Ubuntu 24.04.4 LTS, kernel `7.0.0-30-generic`.
- Memoria Linux visible: ~124 GiB, con 1 GiB de VRAM fija y GTT dinámico de ~124 GiB.
- Runtime recomendado provisionalmente: `llama-vulkan-radv` en Distrobox.
- Modelo y perfil de servicio actuales: Qwen3.8-27B Q4_K_L con MTP, contexto 65 536 y `llama-server` en el puerto 8080.

El servicio expone una API compatible con OpenAI en `http://<EVO_IP>:8080/v1` dentro de la LAN. No debe exponerse directamente a Internet.

## Guía de lectura

- [Arquitectura](docs/architecture.md) y [hardware](docs/hardware.md)
- [Memoria UMA/GTT](docs/memory.md) y [monitorización](docs/monitoring.md)
- [Distrobox y backends](docs/distrobox.md)
- [Nodo de inferencia](docs/inference.md) y [red](docs/networking.md)
- [Benchmarks](docs/benchmarks.md), [diagnóstico](docs/troubleshooting.md) y [roadmap](docs/roadmap.md)

Las copias reproducibles del perfil activo están en [scripts/llama-qwen38.sh](scripts/llama-qwen38.sh) y [systemd/llama-qwen38.service](systemd/llama-qwen38.service). No incluyen el modelo; este repositorio nunca versiona modelos ni credenciales.

## Próximo paso corto

Definir perfiles declarativos y construir `evo-model` para cargar, detener y consultar modelos sin convertir el EVO en el servidor de todos los servicios auxiliares.
