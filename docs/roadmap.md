# Roadmap

## Model manager v1: desplegado

`evo-model` v1 está desplegado para operar un único perfil local mediante
perfiles declarativos, `evo-model.service` y Distrobox. El perfil inicial
`qwen38-q4` valida ruta de modelo, runtime, puerto y health check antes de
declararse listo. El catálogo del repositorio incluye los GGUF inspeccionados
en EVO-X3, pero v1 mantiene un único modelo activo simultáneamente.

## Model manager: siguiente fase

No están implementados múltiples modelos simultáneos, API remota de
administración, integración con N150, LiteLLM, carga automática solicitada por
clientes, evo-top ni descargas automáticas. Una fase posterior deberá decidir
cómo serializar cambios remotos y evitar cargas que compitan por la iGPU.

## Múltiples modelos residentes: experimento futuro

Los ~124 GiB de memoria dinámica permiten explorar modelos pequeños residentes y modelos grandes bajo demanda. Es un experimento, no una capacidad prometida: todos comparten iGPU, ancho de banda de memoria y cómputo. Que dos modelos quepan no significa que generen simultáneamente a máxima velocidad.

## Control plane: futuro

El N150 deberá seleccionar modelos, solicitar load/unload remoto, hacer routing con LiteLLM, integrar agentes y Engram, y potencialmente ofrecer acceso controlado por LAN/Tailscale. El EVO seguirá siendo un endpoint de cómputo, no un host público ni el centro de servicios auxiliares.
