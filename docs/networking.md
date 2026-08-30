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

## Control remoto restringido

El ciclo de vida de los modelos puede controlarse desde el N150 mediante una
clave SSH dedicada configurada manualmente como *forced command*:

```text
N150 -> SSH restricted control -> evo-model-remote -> evo-model -> worker / agent
```

`evo-model-remote` únicamente permite listar, consultar estado y arrancar,
detener o reiniciar las instancias `worker` y `agent`; no proporciona una shell
ni acceso a logs o comandos internos. La inferencia sigue viajando directamente
por HTTP a los puertos 8080/8081. SSH se usa exclusivamente para lifecycle y
control, dentro de la red de confianza, y este mecanismo no debe exponerse a
Internet. La asociación de la clave y el `authorized_keys` no se gestiona desde
este repositorio.

## Comprobación segura

```bash
curl http://<EVO_IP>:8080/v1/models
ss -ltn | rg ':8080|:8081'
```

La primera llamada desde el N150 valida consumo remoto; la segunda, en el EVO, comprueba la escucha local. Un fallo puede ser el servicio, una regla de firewall, una IP errónea o conectividad de capa de red.

## Reversión

Para restringir el servicio al propio EVO, el perfil debe usar `--host 127.0.0.1` y reiniciarse. Eso impide que el N150 lo consuma directamente, por lo que es un cambio arquitectónico que requiere una alternativa de proxy o túnel. No se ha aplicado ningún cambio de red en esta tarea.
