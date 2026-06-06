# Plan 01 — Pruebas en entorno controlado (VirtualBox)

**Proyecto:** rm-MULTIBOOT  
**Autor:** Lic. Ricardo MONLA  
**Fecha de inicio:** 2026-06-06  
**Estado general:** 🔄 En progreso — Fase 1 completada, iniciando Fase 2

---

## Objetivo

Validar el comportamiento del script `rm-multiboot.sh` en un entorno controlado
antes de usarlo en equipos reales. El entorno es una VM Linux en VirtualBox
sobre el equipo local, donde se simula el flujo completo: setup, descarga de
ISOs, generación de entradas GRUB y arranque desde el menú multiboot.

---

## Metodología — Mejora continua por fases

Cada fase tiene:
- **Tareas** con casillas para marcar al completarlas.
- **Notas de ejecución** donde se registra lo que pasó realmente.
- **Conclusión y hallazgos** que se completa al cerrar la fase.

> Los hallazgos de cada fase son **input obligatorio** para revisar y ajustar
> las fases siguientes antes de ejecutarlas. No se avanza a la fase N+1 sin
> haber completado la sección de conclusión de la fase N.

```
Fase 1 ──→ [Conclusión] ──→ Replanteo Fase 2
Fase 2 ──→ [Conclusión] ──→ Replanteo Fase 3
...y así sucesivamente
```

---

## Fases

---

### FASE 1 — Preparación del entorno VirtualBox

**Estado:** ✅ Completada  
**Objetivo:** Tener una VM Linux operativa con disco configurado para simular
un equipo real con espacio libre disponible para crear la partición MULTIBOOT.

#### Especificaciones de la VM — valores reales aplicados

| Parámetro | Valor planificado | Valor aplicado |
|---|---|---|
| Nombre | rm-multiboot-test | rm-multiboot-test ✓ |
| SO base | Debian 12 o Ubuntu 24.04 | Debian 13.5.0 (versión actual) |
| RAM | 2048 MB | 2048 MB ✓ |
| CPU | 2 núcleos | 2 núcleos ✓ |
| Disco principal | 40 GB | 40 GB dinámico VDI ✓ |
| Red | NAT | NAT ✓ |
| Modo firmware | BIOS Legacy | BIOS Legacy ✓ |
| ISO instalación | Debian 12 netinstall | Debian 13.5.0 netinstall (755 MB) |

#### Tareas

- [x] **1.1** Crear la VM en VirtualBox con las especificaciones indicadas
- [x] **1.2** Instalar el SO base *(ver hallazgo #2 — disco usado al 100%, sin espacio libre)*
- [x] **1.3** Verificar con `lsblk -f` — sda1 ext4 40GB al 3%, sda5 swap, sin espacio sin particionar
- [x] **1.4** Instalar dependencias: git, curl, wget, parted, e2fsprogs ✓
- [x] **1.5** Acceso a internet desde la VM: `HTTP/2 301` ✓
- [x] **1.6** Tomar snapshot de VirtualBox con nombre `00-base-limpia`
- [x] **1.7** Repositorio clonado en `/root/rm-MULTIBOOT` ✓
- [x] **1.8** SSH habilitado via VirtualBox Guest Additions + guestcontrol *(ver hallazgo #5)*

#### Notas de ejecución

```
2026-06-06 — Ejecución automatizada con VBoxManage

- VirtualBox 7.1.12 ya instalado en el host
- VM "rm-multiboot-test" creada (UUID: 62cec506-d91a-4ab4-91c7-dbf6e6216e72)
- Disco VDI 40 GB dinámico creado y conectado al controlador SATA
- Controlador IDE agregado para DVD
- ISO Debian 13.5.0 netinstall descargada (755 MB) y conectada al DVD
- Snapshot "00-base-limpia" tomado antes de iniciar la instalación
  (UUID snapshot: 7d07296a-707f-44b3-ada9-5eb9c42b1a69)

HALLAZGO: La URL de Debian en isos.conf estaba desactualizada (12.9.0 → 13.5.0).
Debian ya publicó la versión 13 (Trixie). Requiere actualizar isos.conf.

--- Primera instalación (fallida) ---
- Se instaló Debian 13.5.0 desde la GUI de VirtualBox
- Al reiniciar: pantalla negra con cursor parpadeante = GRUB no instalado en MBR
- Intento de SSH para rescue → sin respuesta (VM no arrancaba)
- Diagnóstico: el instalador probablemente no instaló GRUB correctamente

--- Reinstalación limpia ---
- Se conectó la ISO al DVD y se reinició la VM
- Reinstalación con opción "usar todo el disco" (sin espacio libre)
- GRUB instalado correctamente en /dev/sda
- VM arranca y login funciona: usuario rmonla / Debian 13 (Trixie)

--- Intento de SSH (fallido) ---
- Port forwarding host:2222 → VM:22 configurado y activo
- SSH falla con "Permission denied" — Debian deshabilita PasswordAuthentication por defecto
- Requiere habilitación manual desde consola de la VM (tarea 1.8)

--- Instalación de VirtualBox Guest Additions ---
- ISO /usr/share/virtualbox/VBoxGuestAdditions.iso conectada al DVD via VBoxManage
- Montaje del DVD: mount /dev/cdrom /mnt (ejecutado via scancodes directos)
- Instalador ejecutado: sh /mnt/VBoxLinuxAdditions.run
- Resultado: instalación parcial — faltan linux-headers del kernel
  (kernel 6.12.90+deb13.1-amd64 sin headers instalados)
- A pesar de la instalación parcial, VBoxManage guestcontrol funcionó

--- Habilitación de SSH via guestcontrol ---
- Problema con keymap: VM tiene layout 'es' (España), host tiene 'latam'
  Efecto: '/' → '-', "'" → '{', '-' → "'"
- Solución: crear scripts en el host, copiarlos con 'guestcontrol copyto'
  y ejecutarlos con 'guestcontrol run --exe /usr/bin/sh -- /tmp/script.sh'
- SSH configurado: PasswordAuthentication yes + PermitRootLogin yes
- Conexión SSH verificada: root@127.0.0.1:2222 ✓

--- Estado final del disco (lsblk -f) ---
NAME   FSTYPE  LABEL    FSAVAIL  FSUSE%  MOUNTPOINT
sda
├─sda1 ext4             34.1G    3%      /
├─sda2                                  (extendida)
└─sda5 swap                             [SWAP]
HALLAZGO: Disco 100% particionado — el script debe manejar este escenario real.
```

#### Conclusión y hallazgos
<!-- Se completa al cerrar la fase -->

| # | Hallazgo | Impacto en fase siguiente |
|---|---|---|
| 1 | URLs de Debian en `isos.conf` desactualizadas (v12 → v13) | Actualizar catálogo antes de Fase 3 |
| 2 | Instalación con "todo el disco" no deja espacio libre — **este es el escenario real más común** | El script debe detectar disco lleno y actuar: redimensionar partición existente o pedir al usuario que libere espacio. La Fase 2 prueba justamente eso |
| 3 | Debian deshabilita SSH `PasswordAuthentication` por defecto | En producción no afecta al script; para pruebas se resolvió con guestcontrol |
| 4 | Primera instalación de Debian no instaló GRUB en MBR → pantalla negra | En netinstall hay que confirmar el paso de instalación de GRUB explícitamente |
| 5 | `keyboardputstring` de VBoxManage no maneja diferencia de keymaps (host:latam / VM:es) — chars especiales (`/`, `'`, `-`) llegan incorrectos | Solución definitiva: usar Guest Additions + `guestcontrol copyto` + `guestcontrol run` para automatización; `keyboardputscancode` con KP_Divide para rutas en último recurso |

**¿Se ajusta el plan de la Fase 2?** ✅ Sí  
**Ajustes realizados:** La Fase 2 debe probarse con disco 100% particionado (sin espacio libre). El script debe detectar esta situación y ofrecer opciones al usuario (reducir partición existente, o usar disco secundario). Esto es el escenario real más común.

---

### FASE 2 — Ejecución del setup inicial

**Estado:** 🔄 En progreso  
**Prerequisito:** Fase 1 completada y hallazgos revisados.  
**Objetivo:** Verificar que el wizard de setup detecta correctamente el sistema
y maneja todos los escenarios de disco reales — incluyendo disco 100% particionado.

> **Ajuste post-Fase 1:** La Fase 2 amplía su alcance para incluir la implementación
> y prueba del motor de detección de espacio ampliado (Escenarios 1–4).

#### Escenarios de disco que el script debe cubrir

| # | Escenario | Acción del script |
|---|---|---|
| 1 | Espacio libre sin particionar ≥ 10 GB | Crear partición directamente (ya implementado) |
| 2 | Segundo disco disponible | Ofrecer crear MULTIBOOT en ese disco |
| 3 | Solo espacio libre en filesystem raíz (no en partición) | Generar script de rescue + instrucciones para live CD |
| 4 | Partición no raíz con espacio reutilizable | Redimensionar en caliente |

#### Tareas

- [x] **2.1** Ejecutar el script v2.3.2 y registrar la salida de detección
- [x] **2.2** Verificar detección del sistema:
  - [x] Modo de arranque: **BIOS Legacy** ✓
  - [x] SO detectado: **Debian GNU/Linux 13 (trixie)** ✓
  - [x] Disco principal: **/dev/sda (40G)** ✓
  - [x] Espacio libre: **no encontrado** → error registrado en log ✓
- [x] **2.3** Agregar sistema de log al script → `/var/log/rm-multiboot.log` (v2.4.0)
- [ ] **2.4** Implementar motor de detección de espacio ampliado (Escenarios 1–4)
- [ ] **2.5** Implementar Escenario 3: generar script de rescue para live CD cuando la raíz es la única candidata
- [ ] **2.6** Probar el flujo completo en la VM via modo rescue (DVD Debian → rescue → script generado)
- [ ] **2.7** Verificar resultado post-setup:
  ```bash
  lsblk -f
  grep MULTIBOOT /etc/fstab
  ls /mnt/multiboot/
  cat /etc/grub.d/41_multiboot
  ```
- [ ] **2.8** Verificar que GRUB fue actualizado sin errores:
  ```bash
  grep -i multiboot /boot/grub/grub.cfg
  ```
- [ ] **2.9** Tomar snapshot: `01-post-setup`

#### Notas de ejecución

```
2026-06-06 — Ejecución del script v2.3.2 en la VM via SSH

Salida real del script:
  ✓  Modo de arranque: BIOS Legacy
  ✓  Sistema operativo: Debian GNU/Linux 13 (trixie)
  ✓  Disco principal: /dev/sda (  40G)
  ⚠  Partición MULTIBOOT: no encontrada

  → Opción 1: Preparar este equipo para multiboot

  ✗  No se encontró espacio libre ≥ 10 GB sin asignar en /dev/sda
  Para continuar necesitás liberar espacio con GParted u otra herramienta.

La detección del sistema funciona perfectamente.
El error de espacio libre es correcto — el disco está 100% particionado.
El mensaje al usuario es claro pero la acción siguiente no está implementada en el script.

PENDIENTE: Implementar en el script la estrategia para disco sin espacio libre.
```

#### Conclusión y hallazgos

| # | Hallazgo | Impacto en fase siguiente |
|---|---|---|
| 1 | El script solo maneja espacio libre sin particionar. Con disco 100% usado sale con error y deriva al usuario a GParted. Falta implementar la lógica de redimensionamiento automático. | Antes de continuar la Fase 2, hay que agregar esta funcionalidad al script |
| 2 | La detección del sistema (BIOS/UEFI, OS, disco) funciona correctamente en la VM | Sin impacto negativo |
| 3 | El script no tiene sistema de log — toda la información se pierde al cerrar | Agregar log a `/var/log/rm-multiboot.log` en la próxima versión del script |

**¿Se ajusta el plan de la Fase 3?** 🔲 Sí / 🔲 No  
**Ajustes realizados:** *(pendiente cierre de fase)*

---

### FASE 3 — Prueba de catálogo y descarga de ISOs

**Estado:** 🔲 Pendiente  
**Prerequisito:** Fase 2 completada y hallazgos revisados.  
**Objetivo:** Verificar la descarga desde el catálogo (GitHub), el progreso en
pantalla (barra, %, MB/s, ETA) y la generación correcta de entradas GRUB.

> **Estrategia:** Empezar con una ISO pequeña (Alpine ~200 MB) para ciclar
> rápido. Agregar una ISO mediana (Debian netinstall ~700 MB) en segunda
> instancia.

#### Tareas

- [ ] **3.1** Desde el menú → Agregar ISO → Descargar desde catálogo
- [ ] **3.2** Verificar que el catálogo se carga desde GitHub (mensaje "GitHub — actualizado")
- [ ] **3.3** Seleccionar **Alpine Linux** (ISO pequeña para prueba rápida)
- [ ] **3.4** Verificar que se muestran correctamente durante la descarga:
  - [ ] Barra de progreso `[####----]`
  - [ ] Porcentaje `%`
  - [ ] MB actuales / MB totales
  - [ ] Velocidad en MB/s
  - [ ] ETA en `mm:ss`
- [ ] **3.5** Verificar post-descarga:
  ```bash
  ls -lh /mnt/multiboot/isos/
  cat /mnt/multiboot/grub/entries/*.cfg
  grep -i alpine /boot/grub/grub.cfg
  ```
- [ ] **3.6** Repetir descarga con **Debian 12 Netinstall**
- [ ] **3.7** Probar descarga de la ISO de Google Drive (Linux Mint desde Drive)
- [ ] **3.8** Verificar que "ya descargada" aparece si se intenta descargar de nuevo
- [ ] **3.9** Tomar snapshot: `02-post-descargas`

#### Notas de ejecución

```
[ espacio para registrar lo que ocurrió ]
```

#### Conclusión y hallazgos

| # | Hallazgo | Impacto en fase siguiente |
|---|---|---|
| — | *(pendiente)* | — |

**¿Se ajusta el plan de la Fase 4?** 🔲 Sí / 🔲 No  
**Ajustes realizados:** *(ninguno hasta completar esta fase)*

---

### FASE 4 — Prueba de arranque desde GRUB

**Estado:** 🔲 Pendiente  
**Prerequisito:** Fase 3 completada y hallazgos revisados.  
**Objetivo:** Reiniciar la VM y verificar que el menú GRUB muestra las ISOs
y que al menos una arranca correctamente en modo live.

#### Tareas

- [ ] **4.1** Reiniciar la VM
- [ ] **4.2** Verificar que el menú GRUB aparece con las entradas de las ISOs descargadas
- [ ] **4.3** Bootear **Alpine Linux** desde el menú GRUB
  - [ ] Carga el kernel sin error
  - [ ] Llega al prompt de login live
- [ ] **4.4** Reiniciar y bootear **Debian Netinstall** desde el menú GRUB
  - [ ] Aparece el instalador de Debian
- [ ] **4.5** Documentar cualquier error de GRUB (mensajes, pantalla negra, kernel panic)
- [ ] **4.6** Si alguna ISO falla, registrar el mensaje de error exacto y la entrada `.cfg` generada
- [ ] **4.7** Tomar snapshot: `03-post-boot-test`

#### Notas de ejecución

```
[ espacio para registrar lo que ocurrió ]
```

#### Conclusión y hallazgos

| # | Hallazgo | Impacto en fase siguiente |
|---|---|---|
| — | *(pendiente)* | — |

**¿Se ajusta el plan de la Fase 5?** 🔲 Sí / 🔲 No  
**Ajustes realizados:** *(ninguno hasta completar esta fase)*

---

### FASE 5 — Prueba de escenarios avanzados y condiciones adversas

**Estado:** 🔲 Pendiente  
**Prerequisito:** Fase 4 completada y hallazgos revisados.  
**Objetivo:** Validar el comportamiento del script ante escenarios reales de mayor
complejidad: sin red, múltiples discos, tabla GPT, modo UEFI, segunda ejecución.

> **Ajuste post-Fase 2:** "Disco sin espacio libre" ya NO es caso borde —
> es el escenario base implementado en Fase 2. Esta fase prueba escenarios
> adicionales no cubiertos en fases anteriores.

#### Tareas — Sin conexión a internet

- [ ] **5.1** Deshabilitar la red de la VM en VirtualBox
- [ ] **5.2** Ejecutar el script y elegir "Descargar desde catálogo"
- [ ] **5.3** Verificar que cae al fallback local (`isos.conf` junto al script)
- [ ] **5.4** Rehabilitar la red

#### Tareas — Gestión de ISOs

- [ ] **5.5** Probar "Ver ISOs disponibles" y verificar que muestra estado correcto
- [ ] **5.6** Eliminar una ISO desde el menú y verificar:
  ```bash
  ls /mnt/multiboot/isos/
  ls /mnt/multiboot/grub/entries/
  grep -c menuentry /boot/grub/grub.cfg
  ```
- [ ] **5.7** Reiniciar y verificar que la ISO eliminada ya no aparece en GRUB

#### Tareas — Segundo disco (Escenario 2)

- [ ] **5.8** Agregar un segundo disco VDI a la VM desde el host
- [ ] **5.9** Verificar que el script detecta el segundo disco y lo ofrece como destino
- [ ] **5.10** Completar el setup usando el segundo disco

#### Tareas — Modo UEFI

- [ ] **5.11** Restaurar snapshot `00-base-limpia`
- [ ] **5.12** Cambiar la VM a modo EFI en VirtualBox (Configuración → Sistema → Habilitar EFI)
- [ ] **5.13** Reinstalar el SO base en modo UEFI
- [ ] **5.14** Repetir el setup con `rm-multiboot.sh` y verificar detección UEFI
- [ ] **5.15** Verificar que el hook de GRUB funciona igual en UEFI

#### Notas de ejecución

```
[ espacio para registrar lo que ocurrió ]
```

#### Conclusión y hallazgos

| # | Hallazgo | Impacto en fase siguiente |
|---|---|---|
| — | *(pendiente)* | — |

**¿Se ajusta el plan de la Fase 6?** 🔲 Sí / 🔲 No  
**Ajustes realizados:** *(ninguno hasta completar esta fase)*

---

### FASE 6 — Correcciones, optimizaciones y cierre

**Estado:** 🔲 Pendiente  
**Prerequisito:** Fases 1–5 completadas y hallazgos consolidados.  
**Objetivo:** Aplicar todos los fixes identificados, re-validar los casos que
fallaron y documentar el estado final del script para uso en producción.

#### Tareas

- [ ] **6.1** Consolidar todos los bugs encontrados en las fases anteriores
- [ ] **6.2** Priorizar fixes por impacto (bloqueante / menor / cosmético)
- [ ] **6.3** Implementar y commitear cada fix por separado con mensaje descriptivo
- [ ] **6.4** Re-ejecutar los casos que fallaron en las fases anteriores
- [ ] **6.5** Actualizar `isos.conf` si se detectaron URLs rotas o desactualizadas
- [ ] **6.6** Actualizar versión del script según la magnitud de los cambios
- [ ] **6.7** Hacer push final al repositorio
- [ ] **6.8** Documentar el estado "apto para uso en equipos reales" o las condiciones pendientes

#### Notas de ejecución

```
[ espacio para registrar lo que ocurrió ]
```

#### Conclusión y hallazgos — Cierre del plan

| # | Hallazgo / Resultado | Acción tomada |
|---|---|---|
| — | *(pendiente)* | — |

**Bugs encontrados:** 0 *(actualizar)*  
**Bugs resueltos:** 0 *(actualizar)*  
**Pendientes para próximo ciclo:** *(ninguno hasta completar)*

---

## Registro de versiones del script durante las pruebas

| Fase | Versión del script | Cambios relevantes |
|---|---|---|
| Inicio | 2.3.2 | Versión inicial de pruebas |
| — | — | — |

---

## Checklist general de avance

- [x] Fase 1 — Entorno VirtualBox preparado
- [ ] Fase 2 — Setup inicial validado
- [ ] Fase 3 — Descargas y catálogo validados
- [ ] Fase 4 — Arranque GRUB validado
- [ ] Fase 5 — Casos borde validados
- [ ] Fase 6 — Correcciones aplicadas y plan cerrado
