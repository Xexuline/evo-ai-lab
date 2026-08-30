# Red y exposición del servicio

## Estado actual

Las instancias de `llama-server` usan el host definido por el perfil y puertos efectivos: `worker` 8080 y `agent` 8081. Los endpoints OpenAI-compatible son:

```text
http://<EVO_IP>:8080/v1
http://<EVO_IP>:8081/v1
```

La dirección concreta del EVO no se versiona: cambia con DHCP y no es necesaria para reproducir el diseño. La accesibilidad efectiva depende además del firewall y de la topología LAN, que no se modificaron ni se inventarían aquí.

## Decisión

Escuchar en todas las interfaces permite que el N150 consuma el nodo de inferencia. Esta apertura es solo para la red de confianza. El EVO no debe exponerse directamente a Internet.

En una fase posterior, el N150 podrá proporcionar routing y acceso controlado a través de LiteLLM y, potencialmente, LAN/Tailscale. Esa capa no está implementada ni verificada en este repositorio.

## Comprobación segura

```bash
curl http://<EVO_IP>:8080/v1/models
ss -ltn | rg ':8080|:8081'
```

La primera llamada desde el N150 valida consumo remoto; la segunda, en el EVO, comprueba la escucha local. Un fallo puede ser el servicio, una regla de firewall, una IP errónea o conectividad de capa de red.

## Reversión

Para restringir el servicio al propio EVO, el perfil debe usar `--host 127.0.0.1` y reiniciarse. Eso impide que el N150 lo consuma directamente, por lo que es un cambio arquitectónico que requiere una alternativa de proxy o túnel. No se ha aplicado ningún cambio de red en esta tarea.
