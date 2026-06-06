# Plan 01 — Pruebas en entorno controlado (VirtualBox)

**Proyecto:** rm-MULTIBOOT  
**Autor:** Lic. Ricardo MONLA  
**Fecha de inicio:** 2026-06-06  
**Estado general:** 🔄 En progreso

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

**Estado:** 🔄 En progreso — pendiente instalación del SO en la VM  
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
- [ ] **1.2** Instalar el SO base dejando al menos 15 GB sin asignar en el disco
- [ ] **1.3** Verificar con `lsblk -f` que hay espacio libre sin particionar
- [ ] **1.4** Instalar dependencias necesarias en la VM:
  ```bash
  sudo apt install -y git curl wget parted e2fsprogs
  ```
- [ ] **1.5** Verificar acceso a internet desde la VM:
  ```bash
  curl -Is https://raw.githubusercontent.com | head -1
  ```
- [x] **1.6** Tomar snapshot de VirtualBox con nombre `00-base-limpia`
- [ ] **1.7** Clonar el repositorio dentro de la VM:
  ```bash
  git clone https://github.com/ricardomonla/rm-MULTIBOOT.git ~/rm-MULTIBOOT
  ```

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

PENDIENTE: Iniciar la VM en VirtualBox GUI e instalar Debian 13
dejando ~20 GB sin particionar (tareas 1.2 a 1.7).
```

#### Conclusión y hallazgos
<!-- Se completa al cerrar la fase -->

| # | Hallazgo | Impacto en fase siguiente |
|---|---|---|
| 1 | URLs de Debian en `isos.conf` desactualizadas (v12 → v13) | Actualizar catálogo antes de Fase 3 |
| — | *(resto pendiente hasta completar instalación del SO)* | — |

**¿Se ajusta el plan de la Fase 2?** 🔲 Sí / 🔲 No  
**Ajustes realizados:** *(pendiente cierre de fase)*

---

### FASE 2 — Ejecución del setup inicial

**Estado:** 🔲 Pendiente  
**Prerequisito:** Fase 1 completada y hallazgos revisados.  
**Objetivo:** Verificar que el wizard de setup detecta correctamente el sistema,
encuentra el espacio libre, crea la partición MULTIBOOT y la integra en GRUB.

#### Tareas

- [ ] **2.1** Ejecutar el script como root y registrar la salida de detección:
  ```bash
  sudo ~/rm-MULTIBOOT/rm-multiboot.sh
  ```
- [ ] **2.2** Verificar que la detección muestra correctamente:
  - [ ] Modo de arranque (BIOS/UEFI)
  - [ ] SO detectado
  - [ ] Disco principal correcto
  - [ ] Espacio libre identificado
- [ ] **2.3** Completar el wizard de setup asignando al menos 15 GB
- [ ] **2.4** Verificar resultado post-setup:
  ```bash
  lsblk -f
  grep MULTIBOOT /etc/fstab
  ls /mnt/multiboot/
  cat /etc/grub.d/41_multiboot
  ```
- [ ] **2.5** Verificar que GRUB fue actualizado sin errores:
  ```bash
  grep -i multiboot /boot/grub/grub.cfg
  ```
- [ ] **2.6** Tomar snapshot: `01-post-setup`

#### Notas de ejecución

```
[ espacio para registrar lo que ocurrió ]
```

#### Conclusión y hallazgos

| # | Hallazgo | Impacto en fase siguiente |
|---|---|---|
| — | *(pendiente)* | — |

**¿Se ajusta el plan de la Fase 3?** 🔲 Sí / 🔲 No  
**Ajustes realizados:** *(ninguno hasta completar esta fase)*

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

### FASE 5 — Prueba de casos borde y condiciones adversas

**Estado:** 🔲 Pendiente  
**Prerequisito:** Fase 4 completada y hallazgos revisados.  
**Objetivo:** Validar el comportamiento del script ante situaciones no ideales:
sin red, disco lleno, partición ya existente, modo UEFI, etc.

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

#### Tareas — Modo UEFI

- [ ] **5.8** Restaurar snapshot `00-base-limpia`
- [ ] **5.9** Cambiar la VM a modo EFI en VirtualBox (Configuración → Sistema → Habilitar EFI)
- [ ] **5.10** Reinstalar el SO base en modo UEFI
- [ ] **5.11** Repetir el setup con `rm-multiboot.sh` y verificar detección UEFI
- [ ] **5.12** Verificar que el hook de GRUB funciona igual en UEFI

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

- [ ] Fase 1 — Entorno VirtualBox preparado
- [ ] Fase 2 — Setup inicial validado
- [ ] Fase 3 — Descargas y catálogo validados
- [ ] Fase 4 — Arranque GRUB validado
- [ ] Fase 5 — Casos borde validados
- [ ] Fase 6 — Correcciones aplicadas y plan cerrado
