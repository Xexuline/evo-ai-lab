# Diagnóstico

## El servicio no responde

```bash
evo-model status
evo-model logs worker
evo-model logs agent
ss -ltn | rg ':8080|:8081'
```

Comprueban, respectivamente, el ciclo de vida, los errores recientes y la escucha. Si la unidad no carga, confirmar que `evo-model` y la unidad instalada existen y que la toolbox sigue teniendo el mismo nombre. Si escucha localmente pero no desde el N150, investigar red o firewall sin exponer el EVO a Internet.

## VS Code Snap y Distrobox

Para administrar `evo-model` o diagnosticar Distrobox, usar una terminal normal
del sistema, SSH o systemd. En el terminal integrado de VS Code instalado por
Snap se observó un entorno distinto: `XDG_DATA_HOME` puede apuntar bajo
`~/snap/code/` y `evo-model --validate-runtime qwen38-q4` puede informar que
no encuentra `llama-vulkan-radv`, mientras que el mismo comando funciona desde
una shell normal. No se establece como un bug confirmado de VS Code o
Distrobox; es una diferencia de entorno observada específicamente con VS Code
Snap. La resolución de perfiles de v1 usa deliberadamente
`~/.local/share/evo-model/models` para evitar que ese `XDG_DATA_HOME` altere la
instalación visible, pero se recomienda no usar ese terminal para diagnóstico o
administración de Distrobox.

## La GPU parece tener solo 1 GiB

No diagnosticarlo solo con `nvtop`: 1 GiB es la VRAM fija esperada. Consultar los cuatro archivos `mem_info_{vram,gtt}_{used,total}` de [monitoring.md](monitoring.md). Un GTT alto durante inferencia es normal para el diseño UMA dinámico.

## El modelo no cabe o hay presión de memoria

```bash
free -h
cat /sys/module/ttm/parameters/pages_limit
cat /proc/cmdline
```

Verificar memoria disponible, el límite TTM y que el kernel haya arrancado con `amdgpu.gttsize=126976 ttm.pages_limit=32505856`. Cerrar cargas no relacionadas o elegir un perfil menor son mitigaciones operativas; no modificar GRUB o BIOS sin una decisión explícita y reinicio planificado.

## No aparece la GPU en la toolbox

```bash
distrobox list
distrobox enter llama-vulkan-radv -- llama-cli --list-devices
```

Primero validar el host con `lspci`; después validar el runtime. Una actualización de imagen o driver puede cambiar el resultado, por lo que conviene anotar las versiones antes de sustituirla.

## El servicio no persiste tras cerrar sesión

```bash
loginctl show-user "$USER" -p Linger
systemctl --user is-enabled llama-qwen38.service
```

Se esperan `Linger=yes` y una unidad habilitada. Activar linger o habilitar la unidad cambia el estado del sistema; hacerlo solo siguiendo el procedimiento administrativo aprobado.
