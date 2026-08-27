# Roadmap

## Model manager: próximo objetivo

Construir un gestor mínimo con una interfaz como:

```text
evo-model qwen38
evo-model qwen36
evo-model gpt-oss
evo-model stop
evo-model status
```

Gestionará perfiles declarativos y el ciclo de vida de `llama-server`: seleccionar modelo, cargarlo, descargarlo y comunicar estado. Antes de implementarlo hay que decidir dónde viven los perfiles, cómo se valida que un modelo existe sin registrar su contenido, y cómo serializar cambios para que no haya dos cargas compitiendo por la iGPU.

## Múltiples modelos residentes: experimento futuro

Los ~124 GiB de memoria dinámica permiten explorar modelos pequeños residentes y modelos grandes bajo demanda. Es un experimento, no una capacidad prometida: todos comparten iGPU, ancho de banda de memoria y cómputo. Que dos modelos quepan no significa que generen simultáneamente a máxima velocidad.

## Control plane: futuro

El N150 deberá seleccionar modelos, solicitar load/unload remoto, hacer routing con LiteLLM, integrar agentes y Engram, y potencialmente ofrecer acceso controlado por LAN/Tailscale. El EVO seguirá siendo un endpoint de cómputo, no un host público ni el centro de servicios auxiliares.
