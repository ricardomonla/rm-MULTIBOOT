# Multiboot Nativo desde HD — Investigación y Plan

## Objetivo

Reemplazar el pendrive booteable con ISOs por una partición del disco duro interno que permita arrancar distintas ISOs de instalación de Linux directamente, sin depender de hardware externo.

**Flujo deseado:**
```
Reiniciar PC → Menú GRUB → Elegir ISO → Instalar distro en la PC de turno
```

---

## Panorama de Enfoques

### Opción A — GRUB2 Loopback Manual
**¿Qué es?** GRUB2 incluye soporte nativo para montar ISOs en tiempo de arranque (loopback) y pasar el kernel/initrd directamente desde el archivo `.iso` sin descomprimirlo.

**Cómo funciona:**
1. La ISO vive en cualquier partición que GRUB pueda leer (ext4, NTFS, FAT32)
2. GRUB monta la ISO como loop device en tiempo de boot
3. Se carga el kernel + initrd extraídos de adentro de la ISO
4. El kernel recibe un parámetro que le indica dónde está la ISO para continuar

**Requisito clave:** La ISO debe incluir un archivo `boot/grub/loopback.cfg` — la mayoría de distros modernas lo tienen (Ubuntu, Debian, Fedora, Arch, etc.).

**Ejemplo de entrada GRUB:**
```grub
menuentry "Ubuntu 24.04 LTS" {
    set isofile="/isos/ubuntu-24.04-desktop-amd64.iso"
    loopback loop (hd0,3)$isofile
    linux  (loop)/casper/vmlinuz boot=casper iso-scan/filename=$isofile quiet splash
    initrd (loop)/casper/initrd
}
```

**Pros:**
- Sin dependencias externas — GRUB puro
- Control total sobre el menú
- Funciona con BIOS/Legacy y UEFI (con Secure Boot desactivado)

**Contras:**
- Cada ISO requiere una entrada manual en grub.cfg
- Sintaxis varía entre distros (Ubuntu usa `casper`, Fedora usa `rd.live.image`, Arch es diferente)
- Mantenimiento manual al agregar ISOs

---

### Opción B — GLIM (GRUB2 Live ISO Multiboot)
**Repo:** https://github.com/thias/glim

**¿Qué es?** Colección de scripts y configuraciones GRUB prehechas para arrancar múltiples ISOs. Detecta la distro por nombre de archivo y aplica la configuración correcta automáticamente.

**Estructura de uso:**
```
/boot/isos/
  ubuntu/    ← Ubuntu ISOs van aquí
  debian/    ← Debian ISOs van aquí
  fedora/    ← Fedora ISOs van aquí
  arch/      ← Arch Linux ISOs van aquí
  ...
```

**Soporte de particiones:**
- Partición 1: FAT32, etiqueta `GLIM` (100MB mínimo, para el bootloader)
- Partición 2: ext4, etiqueta `GLIMISO` (para ISOs > 4GB que no caben en FAT32)

**Pros:**
- Agregar ISO = copiar archivo a la carpeta correcta
- Soporta > 60 distros out-of-the-box
- Maneja automáticamente las diferencias de sintaxis por distro

**Contras:**
- Diseñado para USB, adaptarlo a HD interno requiere ajustes
- Requiere partición FAT32 separada para el bootloader GLIM
- Puede coexistir con un OS existente, pero necesita configuración adicional

---

### Opción C — Ventoy en Disco Interno
**Repo:** https://github.com/ventoy/Ventoy

**¿Qué es?** Herramienta que convierte un disco (o partición) en un multiboot que simplemente copia ISOs y listo.

**Instalación en HD interno:**
```bash
# Instalar Ventoy en un disco dedicado o partición reservada
sudo sh Ventoy2Disk.sh -I /dev/sdX
# Luego copiar ISOs a la partición Ventoy
```

**Pros:**
- La más simple: copiar ISO → aparece en el menú al reiniciar
- Soporta > 1300 sistemas operativos
- Funciona con BIOS y UEFI (incluyendo Secure Boot)
- Soporta ISO, WIM, IMG, VHD, EFI

**Contras / Riesgo importante:**
- Ventoy toma control del MBR/GPT del disco donde se instala
- Si se instala en el disco del OS actual: **riesgo de romper el boot existente**
- La solución más segura es un **disco físico separado** o un disco dedicado solo a Ventoy
- Durante la instalación de un OS destino, el installer puede confundirse y seleccionar el disco Ventoy

**Mitigación:** Reservar un disco SSD secundario o una segunda unidad NVMe solo para Ventoy.

---

### Opción D — grml-rescueboot (paquete Debian/Ubuntu)
**¿Qué es?** Paquete que se integra con `update-grub`. Escanea `/boot/grml/` y agrega entradas automáticamente al GRUB del sistema.

```bash
sudo apt install grml-rescueboot
# Copiar ISO a /boot/grml/
sudo update-grub  # agrega la entrada automáticamente
```

**Pros:** Extremadamente simple, integrado con el sistema

**Contras:** Diseñado principalmente para ISOs Grml, soporte limitado para otras distros

---

## Comparativa Rápida

| Criterio | A: GRUB Manual | B: GLIM | C: Ventoy HD | D: grml-rescueboot |
|---|---|---|---|---|
| Simplicidad de uso | Baja | Media | Alta | Alta |
| Agregar nueva ISO | Manual | Copiar a carpeta | Copiar a partición | Copiar + update-grub |
| Soporte de distros | Todas* | ~60 | +1300 | Grml + pocas |
| Riesgo para OS actual | Bajo | Bajo | **Alto** | Bajo |
| UEFI Secure Boot | No** | No** | Sí | No** |
| Scripteabilidad | Total | Alta | Alta | Media |

*con entrada GRUB correcta  
**requiere desactivar Secure Boot

---

## Recomendación: Plan en 3 Fases

### Fase 1 — Estructura Base (mínimo viable)

**Arquitectura elegida:** Partición dedicada ext4 en el disco actual + GRUB2 Loopback + script de gestión

**¿Por qué esta combinación?**
- Sin riesgo para el OS actual (es solo una partición nueva)
- Control total (no dependemos de proyectos externos)
- Scripteabilidad completa para automatizar el flujo
- Compatible con BIOS y UEFI

**Pasos:**

1. **Crear partición dedicada** (20–50 GB, ext4, etiqueta `MULTIBOOT`)
   ```bash
   # Identificar disco y espacio libre
   lsblk
   sudo fdisk /dev/sdX   # o parted / gparted
   sudo mkfs.ext4 -L MULTIBOOT /dev/sdXN
   ```

2. **Punto de montaje permanente** en `/etc/fstab`:
   ```
   LABEL=MULTIBOOT  /mnt/multiboot  ext4  defaults,noatime  0  2
   ```

3. **Estructura de carpetas:**
   ```
   /mnt/multiboot/
     isos/
       ubuntu/
       debian/
       fedora/
       arch/
     grub/
       grub.cfg        ← configuración principal
       entries/        ← un .cfg por ISO
   ```

4. **Entradas GRUB:** Agregar a `/etc/grub.d/40_custom` o crear `/etc/grub.d/41_multiboot`:
   ```grub
   menuentry "--- Multiboot ISOs ---" { echo }
   source (hd0,X)/grub/grub.cfg
   ```

### Fase 2 — Script de Gestión (`add-iso.sh`)

Script que dado un archivo ISO:
1. Lo copia a la partición en la carpeta correcta según la distro detectada
2. Genera automáticamente la entrada GRUB para esa ISO
3. Ejecuta `sudo update-grub` para registrarla

```bash
#!/bin/bash
# add-iso.sh <ruta-al-iso>
# Uso: ./add-iso.sh ~/downloads/ubuntu-24.04.iso
```

Detección de distro por nombre: `ubuntu*` → carpeta ubuntu, `debian*` → debian, etc.

### Fase 3 — Mejoras

- Script `list-isos.sh`: listar ISOs disponibles con info de tamaño y fecha
- Script `remove-iso.sh`: eliminar ISO y su entrada GRUB
- Soporte para ISOs con `loopback.cfg` nativo (delegar la config a la propia ISO)
- Considerar migrar a **GLIM** si el número de distros crece mucho

---

## Consideraciones Importantes

### UEFI vs BIOS Legacy
- Si la PC usa **UEFI**, hay que asegurarse de que **Secure Boot esté desactivado** para que GRUB cargue ISOs de terceros
- En UEFI, el GRUB de la partición EFI existente es el que controla el arranque

### ISOs que soportan loopback.cfg (recomendadas)
- Ubuntu / Xubuntu / Kubuntu / Lubuntu
- Debian (live e installer)
- Linux Mint
- Fedora Workstation
- openSUSE
- Manjaro
- Kali Linux

### ISOs con soporte limitado o especial
- Arch Linux: no tiene loopback.cfg, requiere entrada GRUB personalizada
- Windows ISOs: requieren enfoque diferente (memdisk o Ventoy)
- Alpine Linux: funciona pero con parámetros especiales

### Riesgo de confusión del installer
Cuando se arranca una ISO de instalación desde el HD interno y se va a instalar en **otra PC** (escenario típico del usuario), no hay problema porque la ISO corre en la PC fuente como live environment. El riesgo existe si se intenta instalar en la **misma PC** del multiboot.

---

## Próximos Pasos Concretos

1. **Determinar la máquina host:** ¿Qué disco/partición tiene espacio libre? (`lsblk -f`)
2. **Elegir modo boot:** ¿BIOS/Legacy o UEFI? (`[ -d /sys/firmware/efi ] && echo UEFI || echo BIOS`)
3. **Crear la partición MULTIBOOT** con el espacio disponible
4. **Implementar `add-iso.sh`** con soporte inicial para Ubuntu, Debian y Fedora
5. **Probar el boot** con una ISO conocida antes de ampliar

---

## Fuentes y Referencias

- [Ubuntu Wiki — GRUB2 ISOBoot](https://help.ubuntu.com/community/Grub2/ISOBoot)
- [ArchWiki — Multiboot USB Drive](https://wiki.archlinux.org/title/Multiboot_USB_drive)
- [GLIM en GitHub (thias)](https://github.com/thias/glim)
- [Ventoy — GitHub oficial](https://github.com/ventoy/Ventoy)
- [LinuxBabe — Boot ISO desde GRUB2](https://www.linuxbabe.com/desktop-linux/boot-from-iso-files-using-grub2-boot-loader)
- [DEV.to — Boot desde ISO sin USB](https://dev.to/oryaacov/how-to-boot-from-iso-file-using-grub-internal-hdd-without-external-usbcd-4a09)
- [grml-rescueboot — GitHub](https://github.com/grml/grml-rescueboot)
- [Loopback.cfg — Super Grub Disk Wiki](https://www.supergrubdisk.org/wiki/Loopback.cfg)
