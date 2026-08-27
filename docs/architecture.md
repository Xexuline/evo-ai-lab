# Arquitectura

## Estado actual

El laboratorio se divide en dos responsabilidades deliberadamente separadas:

| Nodo | Papel | Responsabilidades |
| --- | --- | --- |
| EVO-X3 | Plano de cómputo / inferencia | `llama.cpp`, modelos grandes, speculative decoding y herramientas directamente ligadas a inferencia |
| N150 (16 GB) | Plano de control existente | Control, automatización y servicios auxiliares del laboratorio |

El N150 existe y cumple el papel de control plane, pero no fue inspeccionado ni modificado para esta documentación. Por ello no se afirma qué servicios concretos están activos. La integración completa con el EVO y servicios como LiteLLM, Engram, Herdr, Gentle-AI, agentes y routing permanecen previstos o en evolución hasta verificarlos.

## Decisión

El EVO concentra RAM, ancho de banda y la iGPU que necesita la inferencia. Mantener los servicios auxiliares en el N150 reduce la competencia por esos recursos y simplifica el diagnóstico del nodo de cómputo. El N150 puede consumir la API OpenAI-compatible del EVO por LAN; el control remoto completo de cambios de modelo es una integración futura.

## Comprobación

En el EVO, verificar que el servidor esté disponible en `http://<EVO_IP>:8080/v1/models`. Desde el N150, usar la misma URL sustituyendo el placeholder por la dirección LAN del EVO. La conectividad y el control de acceso se describen en [networking.md](networking.md).

## Límite de la decisión

Esto no impide ejecutar una herramienta puntual en el EVO para depuración. Sí evita convertirlo en el destino permanente de bases de datos, gateways, agentes y automatizaciones no relacionadas con inferencia.
