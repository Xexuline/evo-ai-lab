# Diagnóstico

## El servicio no responde

```bash
systemctl --user status llama-qwen38.service
journalctl --user -u llama-qwen38.service -n 100 --no-pager
ss -ltn | rg ':8080'
```

Comprueban, respectivamente, el ciclo de vida, los errores recientes y la escucha. Si la unidad no carga, confirmar que `ExecStart` apunta al script existente y ejecutable y que la toolbox sigue teniendo el mismo nombre. Si escucha localmente pero no desde el N150, investigar red o firewall sin exponer el EVO a Internet.

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
