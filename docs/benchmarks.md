# Benchmarks de modelos

## Fuente y alcance

Las conclusiones proceden de Project Pulse / `agent-tests`. Sus artefactos completos no se copian aquí. Son resultados conocidos de ejecuciones agentic, no una batería reproducida durante esta inspección.

| Perfil | Resultado conocido |
| --- | ---: |
| Qwen3.8-27B Q4_K_L + MTP | 64/100 con RADV y también 64/100 con ROCm |
| Qwen3.8 Q8 | 56/100 |
| Qwen3.8 Q5_K_M | 53/100 |
| GPT-OSS-120B MXFP4 | 24/100 |
| Qwen3.6 + MTP + NGRAM | 23/100 |
| Qwen3.6 + MTP | 14/100 |
| Qwen3-Coder-Next Q5_K_M | 12/100 |

## Decisión actual

Qwen3.8-27B Q4_K_L + MTP es el candidato práctico preferido hasta ahora. Además de su score, destacó por throughput y consumo de memoria. RADV continúa como backend recomendado; ROCm se conserva para futuras reevaluaciones.

Una ejecución agentic tiene variabilidad. Estos scores no demuestran que una cuantización menor sea intrínsecamente más inteligente: cambian el perfil de memoria, velocidad, backend, sampler, contexto, MTP y condiciones de ejecución. No se inventan métricas de throughput, latencia o acceptance que no estén verificadas aquí.

## Cómo reevaluar

Usar Project Pulse / `agent-tests`, fijar versión de llama.cpp, backend, modelo, parámetros de servidor y suite, y conservar resultados fuera de este repositorio. Comparar varias ejecuciones y documentar configuración y dispersión antes de promover un nuevo perfil.
