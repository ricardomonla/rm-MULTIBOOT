#!/usr/bin/env bash
# =============================================================================
#  rm-multiboot.sh — Gestor de Multiboot desde disco interno
# =============================================================================
#  Autor:    Lic. Ricardo MONLA
#  Email:    rmonla@gmail.com
#  GitHub:   https://github.com/ricardomonla/rm-MULTIBOOT
#  Versión:  2.3.2
#  Licencia: MIT
#
#  Uso: sudo ./rm-multiboot.sh
#
#  Descripción:
#    Prepara una partición del disco interno para bootear ISOs de Linux
#    directamente desde el menú GRUB, sin necesidad de pendrive.
#    Las ISOs se pueden descargar desde el catálogo (isos.conf) o
#    agregarse desde un archivo local.
# =============================================================================
set -euo pipefail

# ─── Constantes ───────────────────────────────────────────────────────────────
readonly SCRIPT_VERSION="2.5.0"
readonly SCRIPT_AUTHOR="Lic. Ricardo MONLA"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ISOS_CONF="$SCRIPT_DIR/isos.conf"
readonly ISOS_CONF_URL="https://raw.githubusercontent.com/ricardomonla/rm-MULTIBOOT/main/isos.conf"

readonly MULTIBOOT_LABEL="MULTIBOOT"
readonly MULTIBOOT_MOUNT="/mnt/multiboot"
readonly ISO_DIR="$MULTIBOOT_MOUNT/isos"
readonly ENTRIES_DIR="$MULTIBOOT_MOUNT/grub/entries"
readonly GRUB_HOOK="/etc/grub.d/41_multiboot"
readonly LOG_FILE="/var/log/rm-multiboot.log"

# ─── Colores ──────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
B='\033[0;34m' C='\033[0;36m' W='\033[1m' N='\033[0m'

# ─── Log ──────────────────────────────────────────────────────────────────────
log() {
    local level="$1"; shift
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG_FILE" 2>/dev/null
}
log_info()  { log INFO  "$*"; }
log_warn()  { log WARN  "$*"; }
log_err()   { log ERROR "$*"; }
log_step()  { log STEP  "=== $* ==="; }

# ─── Estado global (poblado por detect_system) ────────────────────────────────
BOOT_MODE="" OS_NAME="" ROOT_DISK_DEV="" ROOT_DISK_SIZE=""
MULTIBOOT_DEV="" MULTIBOOT_SIZE="" MULTIBOOT_READY=false


# =============================================================================
# UI
# =============================================================================

banner() {
    clear
    echo -e "${W}${B}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║   rm-multiboot  ·  v${SCRIPT_VERSION}  ·  ${SCRIPT_AUTHOR}   ║"
    echo "  ╚═══════════════════════════════════════════════════════╝"
    echo -e "${N}"
}

ok()      { echo -e "  ${G}✓${N}  $*"; log_info  "OK: $(echo -e "$*" | sed 's/\x1b\[[0-9;]*m//g')"; }
warn()    { echo -e "  ${Y}⚠${N}  $*"; log_warn  "$(echo -e "$*" | sed 's/\x1b\[[0-9;]*m//g')"; }
err()     { echo -e "  ${R}✗${N}  $*"; log_err   "$(echo -e "$*" | sed 's/\x1b\[[0-9;]*m//g')"; }
step()    { echo -e "\n  ${W}${C}→${N}  ${W}$*${N}"; }
divider() { echo -e "\n  ${B}──────────────────────────────────────────────────────${N}\n"; }

ask() {
    local prompt="$1" default="${2:-}" answer
    if [[ -n "$default" ]]; then
        read -rp "  ${W}$prompt${N} [$default]: " answer
        echo "${answer:-$default}"
    else
        read -rp "  ${W}$prompt${N}: " answer
        echo "$answer"
    fi
}

confirm() {
    local answer
    read -rp "  ${W}$* [s/N]:${N} " answer
    [[ "${answer,,}" == "s" ]]
}

pause() { echo ""; read -rp "  Presioná Enter para continuar..." _; }

grub_update() {
    if command -v update-grub &>/dev/null; then
        update-grub 2>/dev/null && ok "GRUB actualizado" \
            || warn "No se pudo actualizar GRUB automáticamente"
    elif command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null && ok "GRUB actualizado" \
            || warn "No se pudo actualizar GRUB automáticamente"
    else
        warn "No se encontró update-grub — actualizá el GRUB manualmente"
    fi
}


# =============================================================================
# DETECCIÓN DEL SISTEMA
# =============================================================================

detect_system() {
    log_step "Detectando sistema"
    step "Detectando sistema..."
    echo ""

    [[ -d /sys/firmware/efi ]] && BOOT_MODE="UEFI" || BOOT_MODE="BIOS Legacy"
    ok "Modo de arranque: ${W}$BOOT_MODE${N}"

    [[ -f /etc/os-release ]] && { . /etc/os-release; OS_NAME="${PRETTY_NAME:-Linux}"; } \
        || OS_NAME="Linux"
    ok "Sistema operativo: ${W}$OS_NAME${N}"

    local root_src root_name
    root_src=$(findmnt -n -o SOURCE / 2>/dev/null | head -1)
    root_name=$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -1)
    [[ -z "$root_name" ]] && \
        root_name=$(echo "$root_src" | sed 's|/dev/||;s|p\?[0-9]*$||')
    ROOT_DISK_DEV="/dev/$root_name"
    ROOT_DISK_SIZE=$(lsblk -dno SIZE "$ROOT_DISK_DEV" 2>/dev/null || echo "?")
    ok "Disco principal: ${W}$ROOT_DISK_DEV${N} ($ROOT_DISK_SIZE)"

    local mb_name
    mb_name=$(lsblk -o NAME,LABEL -rn 2>/dev/null \
              | awk -v lbl="$MULTIBOOT_LABEL" '$2==lbl {print $1}' | head -1)
    if [[ -n "$mb_name" ]]; then
        MULTIBOOT_DEV="/dev/$mb_name"
        MULTIBOOT_SIZE=$(lsblk -dno SIZE "$MULTIBOOT_DEV" 2>/dev/null || echo "?")
        MULTIBOOT_READY=true
        ok "Partición MULTIBOOT: ${W}$MULTIBOOT_DEV${N} ($MULTIBOOT_SIZE) ${G}lista${N}"
    else
        MULTIBOOT_READY=false
        warn "Partición MULTIBOOT: ${Y}no encontrada${N}"
    fi
}


# =============================================================================
# MENÚ PRINCIPAL
# =============================================================================

menu_principal() {
    divider

    if [[ "$MULTIBOOT_READY" == false ]]; then
        echo -e "  Hola. Este equipo aún no tiene partición MULTIBOOT."
        echo -e "  Voy a crearla en espacio libre del disco ${W}$ROOT_DISK_DEV${N}"
        echo -e "  para que puedas bootear ISOs sin pendrive.\n"
        echo "    1)  Preparar este equipo para multiboot"
        echo "    2)  Salir"
        echo ""
        local opt; opt=$(ask "Opción [1-2]")
        case "$opt" in
            1) setup_wizard ;;
            2) echo ""; exit 0 ;;
            *) menu_principal ;;
        esac
    else
        mount_multiboot
        local iso_count
        iso_count=$(find "$ISO_DIR" -maxdepth 2 -name "*.iso" 2>/dev/null | wc -l)
        [[ "$iso_count" -gt 0 ]] && show_iso_mini_list \
            || echo -e "  ${Y}Todavía no hay ISOs cargadas.${N}\n"
        echo "    1)  Agregar una ISO"
        echo "    2)  Ver ISOs disponibles"
        echo "    3)  Eliminar una ISO"
        echo "    4)  Salir"
        echo ""
        local opt; opt=$(ask "Opción [1-4]")
        case "$opt" in
            1) menu_agregar_iso ;;
            2) list_isos; pause; banner; detect_system; menu_principal ;;
            3) remove_iso ;;
            4) echo ""; exit 0 ;;
            *) menu_principal ;;
        esac
    fi
}

show_iso_mini_list() {
    local count
    count=$(find "$ISO_DIR" -maxdepth 2 -name "*.iso" 2>/dev/null | wc -l)
    echo -e "  ISOs disponibles: ${W}$count${N}\n"
    find "$ISO_DIR" -maxdepth 2 -name "*.iso" 2>/dev/null | sort | while read -r iso; do
        local sz; sz=$(du -h "$iso" | cut -f1)
        printf "    ${C}•${N} %-52s %s\n" "$(basename "$iso")" "($sz)"
    done
    echo ""
}


# =============================================================================
# MENÚ — CÓMO AGREGAR ISO
# =============================================================================

menu_agregar_iso() {
    banner
    step "Agregar una ISO"
    echo ""
    echo -e "  ¿De dónde obtenés la ISO?\n"
    echo "    1)  Descargar desde el catálogo  (isos.conf)"
    echo "    2)  Usar un archivo local        (ruta en este equipo)"
    echo "    3)  Volver"
    echo ""
    local opt; opt=$(ask "Opción [1-3]")
    case "$opt" in
        1) download_from_catalog ;;
        2) add_iso_local ;;
        3) banner; detect_system; menu_principal ;;
        *) menu_agregar_iso ;;
    esac
}


# =============================================================================
# SETUP WIZARD — crear la partición MULTIBOOT
# =============================================================================

# Devuelve todos los bloques de espacio libre ≥ 10 GiB en un disco dado.
# Salida por línea: START_MiB END_MiB SIZE_MiB DISK
_free_blocks_on_disk() {
    local disk="$1"
    parted -s "$disk" unit MiB print free 2>/dev/null \
        | awk -v disk="$disk" \
            '/Free Space/ && $3+0 >= 10240 {
                gsub(/MiB/,"",$1); gsub(/MiB/,"",$2); gsub(/MiB/,"",$3)
                print $1, $2, $3, disk
            }'
}

# Detecta todos los destinos disponibles para crear MULTIBOOT.
# Popula los arrays globales TARGET_LABEL[], TARGET_DISK[], TARGET_START[],
# TARGET_SIZE_GIB[], TARGET_SCENARIO[]
# Escenario 1: espacio sin particionar en cualquier disco
# Escenario 2: disco entero sin particiones (disco secundario virgen)
# Escenario 3: partición no-raíz con filesystem con espacio libre ≥ 10 GiB
# Escenario 4: partición raíz con filesystem con espacio libre ≥ 10 GiB (requiere rescue)
declare -a TARGET_LABEL TARGET_DISK TARGET_START TARGET_SIZE_GIB TARGET_SCENARIO
detect_targets() {
    TARGET_LABEL=(); TARGET_DISK=(); TARGET_START=()
    TARGET_SIZE_GIB=(); TARGET_SCENARIO=()

    local all_disks
    mapfile -t all_disks < <(lsblk -dno NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}')

    # Escenario 1: espacio libre sin particionar
    local disk block
    for disk in "${all_disks[@]}"; do
        while read -r start _ size_mib bdisk; do
            local gib=$(( size_mib / 1024 ))
            TARGET_LABEL+=("Espacio libre en $bdisk (~${gib} GB)")
            TARGET_DISK+=("$bdisk")
            TARGET_START+=("$start")
            TARGET_SIZE_GIB+=("$gib")
            TARGET_SCENARIO+=("1")
        done < <(_free_blocks_on_disk "$disk")
    done

    # Escenario 2: disco sin ninguna partición (virgen o vacío)
    for disk in "${all_disks[@]}"; do
        [[ "$disk" == "$ROOT_DISK_DEV" ]] && continue
        local part_count
        part_count=$(lsblk -lno NAME "$disk" 2>/dev/null | grep -v "^$(basename "$disk")$" | wc -l)
        if [[ "$part_count" -eq 0 ]]; then
            local gib
            gib=$(lsblk -dno SIZE "$disk" | awk '{
                if ($1~/G$/) {sub(/G$/,"",$1); printf "%d", $1}
                else if ($1~/T$/) {sub(/T$/,"",$1); printf "%d", $1*1024}
            }')
            TARGET_LABEL+=("Disco completo $disk (~${gib} GB, sin particiones)")
            TARGET_DISK+=("$disk")
            TARGET_START+=("1")
            TARGET_SIZE_GIB+=("$gib")
            TARGET_SCENARIO+=("2")
        fi
    done

    # Escenarios 3 y 4: particiones con filesystem con espacio libre
    local part mp avail_kb avail_gib
    while read -r part mp; do
        [[ -z "$mp" || "$mp" == "[SWAP]" ]] && continue
        avail_kb=$(df --output=avail "$mp" 2>/dev/null | tail -1 | tr -d ' ')
        [[ -z "$avail_kb" || "$avail_kb" -lt $((10 * 1024 * 1024)) ]] && continue
        avail_gib=$(( avail_kb / 1024 / 1024 ))
        if [[ "$mp" == "/" ]]; then
            TARGET_LABEL+=("Reducir partición raíz $part (${avail_gib} GB libres — requiere rescue)")
            TARGET_SCENARIO+=("4")
        else
            TARGET_LABEL+=("Reducir partición $part montada en $mp (${avail_gib} GB libres)")
            TARGET_SCENARIO+=("3")
        fi
        TARGET_DISK+=("$(lsblk -no PKNAME "$part" 2>/dev/null | head -1 | sed 's/^/\/dev\//')")
        TARGET_START+=("")
        TARGET_SIZE_GIB+=("$avail_gib")
    done < <(lsblk -lno PATH,MOUNTPOINT 2>/dev/null | grep -v '^$')
}

setup_wizard() {
    log_step "Setup wizard"
    banner
    step "Analizando opciones de disco disponibles..."
    echo ""

    detect_targets

    if [[ "${#TARGET_LABEL[@]}" -eq 0 ]]; then
        log_err "No se encontró ningún destino viable para MULTIBOOT"
        err "No se encontró espacio disponible en ningún disco."
        echo -e "\n  El disco tiene menos de 10 GB libres en cualquier partición o región."
        echo -e "  Opciones: agregar un disco secundario o liberar espacio manualmente.\n"
        pause; exit 1
    fi

    echo -e "  Destinos disponibles para la partición ${W}MULTIBOOT${N}:\n"
    local i=1
    for label in "${TARGET_LABEL[@]}"; do
        local sc="${TARGET_SCENARIO[$((i-1))]}"
        local tag=""
        [[ "$sc" == "4" ]] && tag=" ${Y}[requiere rescue]${N}"
        printf "    ${C}%d)${N}  %s%b\n" "$i" "$label" "$tag"
        i=$(( i + 1 ))
    done
    echo "    0)  Salir"
    echo ""

    local opt
    opt=$(ask "¿Qué destino usar? [0-${#TARGET_LABEL[@]}]" "1")
    [[ "$opt" == "0" ]] && { echo ""; exit 0; }

    if ! [[ "$opt" =~ ^[0-9]+$ ]] || \
       [[ "$opt" -lt 1 ]] || [[ "$opt" -gt "${#TARGET_LABEL[@]}" ]]; then
        err "Opción inválida."; pause; setup_wizard; return
    fi

    local idx=$(( opt - 1 ))
    local scenario="${TARGET_SCENARIO[$idx]}"
    local target_disk="${TARGET_DISK[$idx]}"
    local max_gib="${TARGET_SIZE_GIB[$idx]}"

    log_info "Escenario seleccionado: $scenario — ${TARGET_LABEL[$idx]}"

    case "$scenario" in
        1|2) _wizard_create_partition "$target_disk" "${TARGET_START[$idx]}" "$max_gib" "$scenario" ;;
        3)   _wizard_resize_nonroot "$target_disk" "$max_gib" ;;
        4)   _wizard_rescue_root "$target_disk" "$max_gib" ;;
    esac
}

# Escenarios 1 y 2: crear partición en espacio libre o disco virgen
_wizard_create_partition() {
    local disk="$1" start_mib="$2" max_gib="$3" scenario="$4"

    local recommended=$(( max_gib > 100 ? 50 : max_gib ))
    echo ""
    echo -e "  ${Y}Nota:${N} cada ISO pesa entre 600 MB y 5 GB."
    echo -e "  Recomendado: ≥ 30 GB para tener varias ISOs.\n"
    local size_gb
    size_gb=$(ask "¿Cuántos GB asignar a MULTIBOOT? (máx $max_gib)" "$recommended")

    if ! [[ "$size_gb" =~ ^[0-9]+$ ]] || \
       [[ "$size_gb" -lt 10 ]] || [[ "$size_gb" -gt "$max_gib" ]]; then
        err "Tamaño inválido. Debe ser entre 10 y $max_gib."; pause
        setup_wizard; return
    fi

    local end_mib=$(( start_mib + size_gb * 1024 ))

    echo ""
    echo -e "  ${W}Resumen:${N}"
    echo -e "    Disco:            $disk"
    echo -e "    Tamaño:           ${size_gb} GB"
    echo -e "    Etiqueta:         $MULTIBOOT_LABEL"
    echo -e "    Sistema de archivos: ext4"
    echo -e "    Punto de montaje: $MULTIBOOT_MOUNT"
    echo ""

    if ! confirm "¿Crear la partición ahora?"; then
        echo ""; warn "Operación cancelada."; pause; exit 0
    fi

    echo ""
    step "Creando partición..."

    # En escenario 2 (disco virgen) inicializar tabla de particiones primero
    if [[ "$scenario" == "2" ]]; then
        parted -s "$disk" mklabel gpt 2>/dev/null
        start_mib=1
        end_mib=$(( start_mib + size_gb * 1024 ))
    fi

    local parts_before
    parts_before=$(lsblk -lno NAME "$disk" \
                   | grep -v "^$(basename "$disk")$" | sort)

    local part_table
    part_table=$(parted -s "$disk" print 2>/dev/null \
                 | awk '/Partition Table/{print $3}')

    if [[ "$part_table" == "gpt" ]]; then
        parted -s "$disk" mkpart "$MULTIBOOT_LABEL" ext4 \
            "${start_mib}MiB" "${end_mib}MiB" 2>/dev/null
    else
        parted -s "$disk" mkpart primary ext4 \
            "${start_mib}MiB" "${end_mib}MiB" 2>/dev/null
    fi

    sleep 1; partprobe "$disk" 2>/dev/null || true; sleep 1

    local new_part
    new_part=$(comm -13 \
        <(echo "$parts_before") \
        <(lsblk -lno NAME "$disk" \
          | grep -v "^$(basename "$disk")$" | sort) \
        | head -1)

    if [[ -z "$new_part" ]]; then
        err "No se pudo identificar la nueva partición. Revisá con 'lsblk'."
        pause; exit 1
    fi
    MULTIBOOT_DEV="/dev/$new_part"
    ok "Partición creada: $MULTIBOOT_DEV"

    _wizard_format_and_mount "$size_gb"
}

# Escenario 3: redimensionar partición no-raíz en caliente
_wizard_resize_nonroot() {
    local disk="$1" avail_gib="$2"
    warn "Esta operación redimensionará una partición montada."
    echo -e "  El filesystem se reducirá primero con resize2fs y luego se ajusta la partición.\n"

    local size_gb
    size_gb=$(ask "¿Cuántos GB liberar para MULTIBOOT? (máx $avail_gib)" "20")
    if ! [[ "$size_gb" =~ ^[0-9]+$ ]] || [[ "$size_gb" -lt 10 ]]; then
        err "Tamaño inválido."; pause; setup_wizard; return
    fi

    if ! confirm "¿Continuar? Esta operación modifica la tabla de particiones."; then
        echo ""; warn "Cancelado."; pause; exit 0
    fi

    warn "Redimensionamiento en caliente no disponible aún en esta versión."
    echo -e "  Usá el modo rescue (opción de partición raíz) para mayor seguridad.\n"
    log_warn "Escenario 3 (resize no-raíz) no implementado aún"
    pause; setup_wizard
}

# Escenario 4: la única opción es reducir la raíz — generar script rescue
_wizard_rescue_root() {
    local root_disk="$1" avail_gib="$2"
    local rescue_script="/root/rm-multiboot-rescue.sh"
    local safety_margin=10
    local max_free=$(( avail_gib - safety_margin ))

    if [[ "$max_free" -lt 10 ]]; then
        err "Espacio insuficiente: el filesystem raíz tiene solo ${avail_gib} GB libres."
        echo -e "  Se necesitan al menos $((10 + safety_margin)) GB libres en / para continuar.\n"
        pause; exit 1
    fi

    echo ""
    echo -e "  ${Y}El disco no tiene espacio sin particionar.${N}"
    echo -e "  La partición raíz tiene ${W}${avail_gib} GB libres${N} que pueden redistribuirse.\n"
    echo -e "  ${W}Solución:${N} rm-multiboot genera un script que se ejecuta desde un"
    echo -e "  ${W}Live CD / modo rescue${N} para reducir la raíz y crear MULTIBOOT.\n"

    local recommended=$(( max_free > 50 ? 30 : max_free ))
    local size_gb
    size_gb=$(ask "¿Cuántos GB asignar a MULTIBOOT? (máx disponible: $max_free)" "$recommended")

    if ! [[ "$size_gb" =~ ^[0-9]+$ ]] || \
       [[ "$size_gb" -lt 10 ]] || [[ "$size_gb" -gt "$max_free" ]]; then
        err "Tamaño inválido. Debe ser entre 10 y $max_free."; pause
        setup_wizard; return
    fi

    step "Generando script de rescue..."

    # Obtener datos del disco actual
    local root_part root_part_num root_size_mib new_root_end_mib mb_start_mib mb_end_mib
    root_part=$(findmnt -n -o SOURCE / | head -1)
    root_part_num=$(parted -s "$root_disk" print 2>/dev/null \
        | awk -v part="$root_part" '$0 ~ part {print $1}' | head -1)
    [[ -z "$root_part_num" ]] && root_part_num=$(echo "$root_part" | grep -o '[0-9]*$')
    root_size_mib=$(parted -s "$root_disk" unit MiB print 2>/dev/null \
        | awk -v n="$root_part_num" '$1==n {gsub(/MiB/,"",$3); print $3}')
    local keep_mib=$(( root_size_mib - size_gb * 1024 ))
    local root_start_mib
    root_start_mib=$(parted -s "$root_disk" unit MiB print 2>/dev/null \
        | awk -v n="$root_part_num" '$1==n {gsub(/MiB/,"",$2); print $2}')
    new_root_end_mib=$(( root_start_mib + keep_mib ))
    mb_start_mib="$new_root_end_mib"
    mb_end_mib=$(( mb_start_mib + size_gb * 1024 ))
    local part_table
    part_table=$(parted -s "$root_disk" print 2>/dev/null | awk '/Partition Table/{print $3}')

    cat > "$rescue_script" << RESCUE
#!/bin/bash
# =============================================================================
#  rm-multiboot-rescue.sh — Script de redimensionamiento para modo rescue
#  Generado por rm-multiboot.sh v${SCRIPT_VERSION} el $(date '+%Y-%m-%d %H:%M:%S')
#  EJECUTAR DESDE LIVE CD O MODO RESCUE — NO ejecutar con el sistema montado
# =============================================================================
set -euo pipefail
DISK="$root_disk"
ROOT_PART="$root_part"
ROOT_PART_NUM="$root_part_num"
MB_LABEL="$MULTIBOOT_LABEL"
MB_MOUNT="$MULTIBOOT_MOUNT"
PART_TABLE="$part_table"
KEEP_MIB=$keep_mib
ROOT_START_MIB=$root_start_mib
NEW_ROOT_END_MIB=$new_root_end_mib
MB_START_MIB=$mb_start_mib
MB_END_MIB=$mb_end_mib
SIZE_GB=$size_gb

echo "=== rm-multiboot rescue script ==="
echo "Disco: \$DISK | Raíz: \$ROOT_PART | MULTIBOOT: \${SIZE_GB} GB"
echo ""
echo "ADVERTENCIA: Esta operación modifica particiones."
echo "Asegurate de tener un backup antes de continuar."
read -rp "¿Continuar? [s/N]: " ans
[[ "\${ans,,}" != "s" ]] && exit 0

echo "[1/5] Verificando filesystem raíz..."
e2fsck -f "\$ROOT_PART"

echo "[2/5] Reduciendo filesystem a \${KEEP_MIB} MiB..."
resize2fs "\$ROOT_PART" "\${KEEP_MIB}M"

echo "[3/5] Reduciendo partición raíz..."
if [[ "\$PART_TABLE" == "gpt" ]]; then
    parted -s "\$DISK" resizepart "\$ROOT_PART_NUM" "\${NEW_ROOT_END_MIB}MiB"
else
    parted -s "\$DISK" resizepart "\$ROOT_PART_NUM" "\${NEW_ROOT_END_MIB}MiB"
fi

echo "[4/5] Creando partición MULTIBOOT..."
if [[ "\$PART_TABLE" == "gpt" ]]; then
    parted -s "\$DISK" mkpart "\$MB_LABEL" ext4 "\${MB_START_MIB}MiB" "\${MB_END_MIB}MiB"
else
    parted -s "\$DISK" mkpart primary ext4 "\${MB_START_MIB}MiB" "\${MB_END_MIB}MiB"
fi
partprobe "\$DISK" 2>/dev/null || true; sleep 2

MB_DEV=\$(lsblk -lno NAME "\$DISK" | grep -v "^\$(basename \$DISK)\$" | sort | tail -1)
MB_DEV="/dev/\$MB_DEV"

echo "[5/5] Formateando \$MB_DEV como ext4 con etiqueta \$MB_LABEL..."
mkfs.ext4 -L "\$MB_LABEL" "\$MB_DEV"

echo ""
echo "=== Listo. Reiniciá el sistema normalmente y ejecutá rm-multiboot.sh ==="
RESCUE

    chmod +x "$rescue_script"
    ok "Script generado: ${W}$rescue_script${N}"
    log_info "Script rescue generado: $rescue_script (${size_gb} GB para MULTIBOOT)"

    divider
    echo -e "  ${W}Próximos pasos para completar la instalación:${N}\n"
    echo -e "  ${C}1)${N}  Reiniciá desde un ${W}Live CD${N} (cualquier distro Linux)"
    echo -e "       o desde el ${W}modo rescue${N} del instalador de Debian/Ubuntu\n"
    echo -e "  ${C}2)${N}  Montá la partición raíz y copiá el script:"
    echo -e "       ${W}mount $root_part /mnt${N}"
    echo -e "       ${W}cp /mnt/root/rm-multiboot-rescue.sh /tmp/${N}\n"
    echo -e "  ${C}3)${N}  Ejecutá el script de rescue:"
    echo -e "       ${W}bash /tmp/rm-multiboot-rescue.sh${N}\n"
    echo -e "  ${C}4)${N}  Reiniciá en modo normal y volvé a ejecutar:"
    echo -e "       ${W}sudo ./rm-multiboot.sh${N}\n"
    echo -e "  El script generado está en: ${W}$rescue_script${N}"
    log_step "Fin setup wizard — pendiente rescue"
    pause
}

_wizard_format_and_mount() {
    local size_gb="${1:-?}"
    step "Formateando como ext4..."
    mkfs.ext4 -L "$MULTIBOOT_LABEL" -q "$MULTIBOOT_DEV"
    ok "Formato aplicado con etiqueta '$MULTIBOOT_LABEL'"

    mkdir -p "$MULTIBOOT_MOUNT"
    mount "$MULTIBOOT_DEV" "$MULTIBOOT_MOUNT"
    mkdir -p "$ISO_DIR" "$MULTIBOOT_MOUNT/grub/entries"
    ok "Montada en $MULTIBOOT_MOUNT"

    local part_uuid
    part_uuid=$(lsblk -no UUID "$MULTIBOOT_DEV" | head -1)
    if ! grep -q "$part_uuid" /etc/fstab 2>/dev/null; then
        printf '\n# Partición MULTIBOOT — rm-MULTIBOOT\nUUID=%s  %s  ext4  defaults,noatime  0  2\n' \
            "$part_uuid" "$MULTIBOOT_MOUNT" >> /etc/fstab
        ok "Agregado a /etc/fstab (montaje automático)"
    fi

    install_grub_hook "$part_uuid"

    step "Actualizando GRUB..."
    grub_update

    MULTIBOOT_READY=true
    MULTIBOOT_SIZE="${size_gb}G"

    divider
    echo -e "  ${W}${G}¡Listo! El equipo está preparado para multiboot.${N}"
    echo -e "  Ahora podés agregar ISOs con la opción 1 del menú.\n"
    pause
    banner; detect_system; menu_principal
}


# =============================================================================
# GRUB — HOOK
# =============================================================================

install_grub_hook() {
    local part_uuid="$1"
    cat > "$GRUB_HOOK" <<HOOK
#!/bin/sh
# rm-MULTIBOOT — entradas generadas automáticamente por rm-multiboot.sh
MPOINT="$MULTIBOOT_MOUNT"
ENTRIES="$ENTRIES_DIR"

if ! mountpoint -q "\$MPOINT" 2>/dev/null; then
    mount UUID="$part_uuid" "\$MPOINT" 2>/dev/null || exit 0
fi

for cfg in "\$ENTRIES"/*.cfg; do
    [ -f "\$cfg" ] || continue
    cat "\$cfg"
done
HOOK
    chmod +x "$GRUB_HOOK"
    ok "Hook de GRUB instalado: $GRUB_HOOK"
}


# =============================================================================
# MONTAJE
# =============================================================================

mount_multiboot() {
    if ! mountpoint -q "$MULTIBOOT_MOUNT" 2>/dev/null; then
        mkdir -p "$MULTIBOOT_MOUNT"
        mount -L "$MULTIBOOT_LABEL" "$MULTIBOOT_MOUNT" 2>/dev/null \
        || mount "$MULTIBOOT_DEV" "$MULTIBOOT_MOUNT" 2>/dev/null \
        || { err "No se pudo montar la partición MULTIBOOT."; exit 1; }
    fi
    mkdir -p "$ISO_DIR" "$ENTRIES_DIR"
}


# =============================================================================
# SOPORTE GOOGLE DRIVE
# =============================================================================

# Devuelve true si la URL es de Google Drive
is_gdrive_url() {
    [[ "$1" == *"drive.google.com"* ]]
}

# Extrae el File ID de una URL de Google Drive
gdrive_file_id() {
    local url="$1"
    if [[ "$url" =~ drive\.google\.com/file/d/([a-zA-Z0-9_-]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$url" =~ id=([a-zA-Z0-9_-]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

# Intenta obtener el nombre real del archivo desde el header Content-Disposition
gdrive_real_filename() {
    local file_id="$1"
    local dl_url="https://drive.usercontent.google.com/download?id=${file_id}&export=download&authuser=0&confirm=t"
    local name
    name=$(curl -sIL --connect-timeout 8 "$dl_url" 2>/dev/null \
           | grep -i 'content-disposition' \
           | grep -oP 'filename="?\K[^";\r\n]+' | head -1 | tr -d '\r')
    echo "$name"
}

# Devuelve el Content-Length de una URL (0 si no disponible)
get_remote_size() {
    local url="$1"
    local size
    size=$(curl -sIL --connect-timeout 8 "$url" 2>/dev/null \
           | grep -i '^content-length' | tail -1 | awk '{print $2}' | tr -d '\r')
    echo "${size:-0}"
}

# Descarga URL → DEST mostrando barra de progreso en porcentaje propio.
# Si el servidor no informa Content-Length muestra solo MB descargados.
download_with_progress() {
    local url="$1"
    local dest="$2"

    # Obtener tamaño total
    printf "  Consultando tamaño del archivo..."
    local total_bytes
    total_bytes=$(get_remote_size "$url")
    printf "\r                                    \r"

    # Iniciar descarga en background (salida silenciada)
    if command -v curl &>/dev/null; then
        curl -sL -C - -o "$dest" "$url" &
    elif command -v wget &>/dev/null; then
        wget -q -c -O "$dest" "$url" &
    else
        err "No se encontró curl ni wget."; return 1
    fi
    local dl_pid=$!

    # Loop de progreso
    local done_b pct done_mb total_mb filled empty bar
    local prev_bytes=0 speed_str="0.0" eta_str="--:--"
    local start_time; start_time=$(date +%s)
    while kill -0 "$dl_pid" 2>/dev/null; do
        done_b=0
        [[ -f "$dest" ]] && done_b=$(stat -c%s "$dest" 2>/dev/null || echo 0)
        done_mb=$(( done_b / 1024 / 1024 ))

        # Velocidad instantánea (delta en 0.3 s → MB/s)
        local delta=$(( done_b - prev_bytes ))
        [[ $delta -gt 0 ]] && \
            speed_str=$(awk "BEGIN {printf \"%.1f\", $delta / 0.3 / 1048576}")
        prev_bytes=$done_b

        if [[ "$total_bytes" -gt 0 ]]; then
            pct=$(( done_b * 100 / total_bytes ))
            total_mb=$(( total_bytes / 1024 / 1024 ))
            filled=$(( pct * 20 / 100 ))
            empty=$(( 20 - filled ))
            bar=$(printf '%0.s#' $(seq 1 "$filled"))$(printf '%0.s-' $(seq 1 "$empty"))

            # ETA basada en velocidad promedio desde el inicio (más estable que instantánea)
            local elapsed=$(( $(date +%s) - start_time + 1 ))
            local avg_bps=$(( done_b / elapsed ))
            if [[ $avg_bps -gt 0 ]]; then
                local secs=$(( (total_bytes - done_b) / avg_bps ))
                if [[ $secs -lt 3600 ]]; then
                    eta_str=$(printf "%02d:%02d" $(( secs / 60 )) $(( secs % 60 )))
                else
                    eta_str=$(printf "%d:%02d:%02d" \
                        $(( secs / 3600 )) $(( (secs % 3600) / 60 )) $(( secs % 60 )))
                fi
            fi

            printf "\r  ${C}→${N}  [%-20s]  %3d%%  (%d de %d MB)  %s MB/s  ETA %s  " \
                "$bar" "$pct" "$done_mb" "$total_mb" "$speed_str" "$eta_str"
        else
            printf "\r  ${C}→${N}  %d MB  %s MB/s  " "$done_mb" "$speed_str"
        fi
        sleep 0.3
    done

    wait "$dl_pid"
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        local final_mb
        final_mb=$(( $(stat -c%s "$dest" 2>/dev/null || echo 0) / 1024 / 1024 ))
        printf "\r  ${G}✓${N}  [####################]  100%%  (%d MB)                         \n" \
            "$final_mb"
    fi
    return $rc
}

# Descarga un archivo desde Google Drive con progreso
gdrive_download() {
    local file_id="$1"
    local dest="$2"
    local dl_url="https://drive.usercontent.google.com/download?id=${file_id}&export=download&authuser=0&confirm=t"
    download_with_progress "$dl_url" "$dest"
}


# =============================================================================
# DESCARGAR DESDE CATÁLOGO (isos.conf leído desde GitHub)
# =============================================================================

# Obtiene el catálogo desde GitHub; si falla, intenta con el archivo local.
fetch_catalog() {
    local tmp; tmp=$(mktemp)

    if command -v curl &>/dev/null; then
        curl -fsSL --connect-timeout 8 "$ISOS_CONF_URL" -o "$tmp" 2>/dev/null
    elif command -v wget &>/dev/null; then
        wget -q --timeout=8 -O "$tmp" "$ISOS_CONF_URL" 2>/dev/null
    fi

    # Si el archivo descargado tiene contenido válido, lo usamos
    if [[ -s "$tmp" ]] && grep -q '|' "$tmp" 2>/dev/null; then
        echo "$tmp"
        return 0
    fi

    rm -f "$tmp"

    # Fallback: archivo local junto al script
    if [[ -f "$ISOS_CONF" ]]; then
        echo "$ISOS_CONF"
        return 0
    fi

    return 1
}

download_from_catalog() {
    banner
    step "Descargar ISO desde el catálogo"
    echo ""

    # Obtener catálogo
    local catalog_src catalog_file origin_label
    printf "  Cargando catálogo desde GitHub..."
    if catalog_file=$(fetch_catalog); then
        if [[ "$catalog_file" == "$ISOS_CONF" ]]; then
            origin_label="${Y}(sin red — usando archivo local)${N}"
        else
            origin_label="${G}(GitHub — actualizado)${N}"
        fi
        printf "\r  ${G}✓${N}  Catálogo cargado %b\n\n" "$origin_label"
    else
        printf "\r  ${R}✗${N}  No se pudo obtener el catálogo.\n"
        echo -e "  Verificá la conexión a internet o colocá ${W}isos.conf${N} junto al script.\n"
        pause; banner; detect_system; menu_principal; return
    fi

    # Leer entradas válidas del catálogo (ignorar comentarios y líneas vacías)
    local -a names urls
    while IFS='|' read -r name url; do
        [[ "$name" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${name// }" ]]           && continue
        name="${name#"${name%%[! ]*}"}"; name="${name%"${name##*[! ]}"}"
        url="${url#"${url%%[! ]*}"}";    url="${url%"${url##*[! ]}"}"
        [[ -z "$url" ]] && continue
        names+=("$name")
        urls+=("$url")
    done < "$catalog_file"

    # Limpiar archivo temporal si vino de GitHub
    [[ "$catalog_file" != "$ISOS_CONF" ]] && rm -f "$catalog_file"

    if [[ "${#names[@]}" -eq 0 ]]; then
        err "El catálogo está vacío o no tiene entradas válidas."
        pause; banner; detect_system; menu_principal; return
    fi

    # Mostrar catálogo
    echo -e "  ${W}Catálogo disponible:${N}\n"
    local i=1
    for name in "${names[@]}"; do
        local iso_filename
        iso_filename=$(basename "${urls[$((i-1))]%%\?*}")
        local estado=""
        [[ -f "$ISO_DIR/$iso_filename" ]] && estado=" ${G}[ya descargada]${N}"
        printf "  ${C}%2d)${N}  %-42s%b\n" "$i" "$name" "$estado"
        i=$((i+1))
    done
    echo "   0)  Volver"
    echo ""

    local opt
    opt=$(ask "¿Cuál descargamos? [0-${#names[@]}]")

    if [[ "$opt" == "0" ]]; then
        banner; detect_system; menu_principal; return
    fi

    if ! [[ "$opt" =~ ^[0-9]+$ ]] || \
       [[ "$opt" -lt 1 ]] || [[ "$opt" -gt "${#names[@]}" ]]; then
        err "Opción inválida."; pause; download_from_catalog; return
    fi

    local idx=$((opt - 1))
    local chosen_name="${names[$idx]}"
    local chosen_url="${urls[$idx]}"
    local iso_filename gdrive_id=""

    # ── Resolver filename y origen de descarga ────────────────────────────────
    if is_gdrive_url "$chosen_url"; then
        gdrive_id=$(gdrive_file_id "$chosen_url")
        if [[ -z "$gdrive_id" ]]; then
            err "No se pudo extraer el File ID de la URL de Google Drive."
            pause; banner; detect_system; menu_principal; return
        fi
        # Intentar obtener el nombre real del archivo desde headers
        printf "  Obteniendo nombre del archivo desde Google Drive..."
        iso_filename=$(gdrive_real_filename "$gdrive_id")
        if [[ -z "$iso_filename" ]]; then
            # Fallback: generar nombre desde el nombre del catálogo
            iso_filename=$(echo "$chosen_name" | tr '[:upper:]' '[:lower:]' \
                           | tr ' ' '-' | sed 's/[^a-z0-9._-]//g').iso
        fi
        printf "\r  ${G}✓${N}  Archivo: ${W}%s${N}                    \n" "$iso_filename"
    else
        iso_filename=$(basename "${chosen_url%%\?*}")
    fi

    local dest="$ISO_DIR/$iso_filename"

    echo ""
    echo -e "  ${W}ISO seleccionada:${N}"
    ok "Nombre:   ${W}$chosen_name${N}"
    ok "Archivo:  $iso_filename"
    if [[ -n "$gdrive_id" ]]; then
        ok "Origen:   ${C}Google Drive${N} (ID: $gdrive_id)"
    else
        ok "URL:      ${C}$chosen_url${N}"
    fi
    echo ""

    # Verificar si ya existe
    if [[ -f "$dest" ]]; then
        warn "Esta ISO ya está descargada en la partición MULTIBOOT."
        if ! confirm "¿Descargar de nuevo y sobreescribir?"; then
            banner; detect_system; menu_principal; return
        fi
    fi

    local avail_k
    avail_k=$(df "$MULTIBOOT_MOUNT" --output=avail | tail -1)
    echo -e "  Espacio libre en MULTIBOOT: $(( avail_k / 1024 / 1024 )) GB\n"

    if ! confirm "¿Iniciar descarga?"; then
        banner; detect_system; menu_principal; return
    fi

    # ── Descargar ─────────────────────────────────────────────────────────────
    echo ""
    step "Descargando $iso_filename..."
    echo ""

    local download_url
    if [[ -n "$gdrive_id" ]]; then
        download_url="https://drive.usercontent.google.com/download?id=${gdrive_id}&export=download&authuser=0&confirm=t"
    else
        download_url="$chosen_url"
    fi

    download_with_progress "$download_url" "$dest" \
        || { err "Falló la descarga."; rm -f "$dest"; pause
             banner; detect_system; menu_principal; return; }

    ok "Descarga completada: $iso_filename"

    # Generar entrada GRUB
    step "Generando entrada de arranque..."
    local distro
    distro=$(detect_distro "$iso_filename")
    # Preferir el nombre del catálogo si es más descriptivo
    [[ "$distro" == "Linux" ]] && distro="$chosen_name"
    generate_grub_entry "$iso_filename" "$distro"

    step "Actualizando menú de arranque..."
    grub_update

    divider
    echo -e "  ${W}${G}¡ISO lista!${N}"
    echo -e "  Al reiniciar aparecerá en el menú GRUB.\n"
    pause; banner; detect_system; menu_principal
}


# =============================================================================
# AGREGAR ISO DESDE RUTA LOCAL
# =============================================================================

add_iso_local() {
    banner
    step "Agregar ISO desde archivo local"
    echo ""
    echo -e "  Ingresá la ruta completa al archivo .iso"
    echo -e "  ${Y}Tip:${N} podés arrastrar el archivo directamente a la terminal\n"

    local iso_path
    iso_path=$(ask "Ruta al .iso")
    iso_path="${iso_path/#\~/$HOME}"
    iso_path="${iso_path//\'/}"; iso_path="${iso_path//\"/}"

    if [[ ! -f "$iso_path" ]]; then
        err "Archivo no encontrado: $iso_path"
        pause; banner; detect_system; menu_principal; return
    fi

    local iso_name size distro
    iso_name=$(basename "$iso_path")
    size=$(du -h "$iso_path" | cut -f1)
    distro=$(detect_distro "$iso_name")

    echo ""
    echo -e "  ${W}ISO detectada:${N}"
    ok "Nombre: ${W}$iso_name${N}"
    ok "Tamaño: $size"
    ok "Distro: ${W}$distro${N}"
    echo ""

    local avail_k iso_k
    avail_k=$(df "$MULTIBOOT_MOUNT" --output=avail | tail -1)
    iso_k=$(du -k "$iso_path" | cut -f1)
    if [[ "$iso_k" -ge "$avail_k" ]]; then
        err "Espacio insuficiente en la partición MULTIBOOT."
        echo -e "    Disponible: $(( avail_k / 1024 / 1024 )) GB"
        echo -e "    Necesario:  $(( iso_k  / 1024 / 1024 )) GB"
        pause; banner; detect_system; menu_principal; return
    fi

    if [[ -f "$ISO_DIR/$iso_name" ]]; then
        warn "Ya existe una ISO con ese nombre."
        if ! confirm "¿Sobreescribir?"; then
            banner; detect_system; menu_principal; return
        fi
    fi

    if ! confirm "¿Copiar esta ISO al multiboot?"; then
        banner; detect_system; menu_principal; return
    fi

    echo ""
    step "Copiando ISO..."
    local total dest
    total=$(stat -c%s "$iso_path")
    dest="$ISO_DIR/$iso_name"

    cp "$iso_path" "$dest" &
    local cp_pid=$!
    while kill -0 "$cp_pid" 2>/dev/null; do
        local done_b=0
        [[ -f "$dest" ]] && done_b=$(stat -c%s "$dest" 2>/dev/null || echo 0)
        local pct=$(( total > 0 ? done_b * 100 / total : 0 ))
        printf "\r  ${C}→${N}  %3d%%  (%d MB de %d MB)" \
            "$pct" "$(( done_b / 1024 / 1024 ))" "$(( total / 1024 / 1024 ))"
        sleep 0.4
    done
    wait "$cp_pid"
    printf "\r  ${G}✓${N}  100%%  (%d MB)                              \n" \
        "$(( total / 1024 / 1024 ))"

    step "Generando entrada de arranque..."
    generate_grub_entry "$iso_name" "$distro"

    step "Actualizando menú de arranque..."
    grub_update

    divider
    echo -e "  ${W}${G}¡ISO agregada!${N} Al reiniciar aparecerá en el menú GRUB.\n"
    pause; banner; detect_system; menu_principal
}


# =============================================================================
# DETECCIÓN DE DISTRO (por nombre de archivo)
# =============================================================================

detect_distro() {
    local n="${1,,}"
    case "$n" in
        *kubuntu*)              echo "Kubuntu" ;;
        *xubuntu*)              echo "Xubuntu" ;;
        *lubuntu*)              echo "Lubuntu" ;;
        *ubuntu*)               echo "Ubuntu" ;;
        *linuxmint*|*mint*)     echo "Linux Mint" ;;
        *debian*)               echo "Debian" ;;
        *fedora*)               echo "Fedora" ;;
        *arch*)                 echo "Arch Linux" ;;
        *manjaro*)              echo "Manjaro" ;;
        *kali*)                 echo "Kali Linux" ;;
        *parrot*)               echo "Parrot OS" ;;
        *opensuse*)             echo "openSUSE" ;;
        *pop*|*popos*)          echo "Pop!_OS" ;;
        *elementary*)           echo "elementary OS" ;;
        *zorin*)                echo "Zorin OS" ;;
        *mxlinux*|*mx-*)        echo "MX Linux" ;;
        *tails*)                echo "Tails" ;;
        *alpine*)               echo "Alpine Linux" ;;
        *rockylinux*|*rocky*)   echo "Rocky Linux" ;;
        *almalinux*|*alma*)     echo "AlmaLinux" ;;
        *centos*)               echo "CentOS" ;;
        *)                      echo "Linux" ;;
    esac
}


# =============================================================================
# GENERAR ENTRADA GRUB
# =============================================================================

generate_grub_entry() {
    local iso_name="$1" distro="$2"
    local label="${iso_name%.iso}"
    local part_uuid
    part_uuid=$(lsblk -no UUID "$MULTIBOOT_DEV" 2>/dev/null | head -1)
    local entry_file="$ENTRIES_DIR/${label}.cfg"

    # Verificar si la ISO tiene loopback.cfg nativo
    local tmp_mnt has_loopback=false
    tmp_mnt=$(mktemp -d)
    modprobe loop 2>/dev/null || true
    if mount -o loop,ro "$ISO_DIR/$iso_name" "$tmp_mnt" 2>/dev/null; then
        [[ -f "$tmp_mnt/boot/grub/loopback.cfg" ]] && has_loopback=true
        umount "$tmp_mnt" 2>/dev/null || true
    fi
    rmdir "$tmp_mnt" 2>/dev/null || true

    if [[ "$has_loopback" == true ]]; then
        cat > "$entry_file" <<CFG
menuentry "$distro — $iso_name" --class linux {
    insmod part_gpt
    insmod part_msdos
    insmod ext2
    insmod loopback
    insmod iso9660
    search --no-floppy --fs-uuid --set=isopart $part_uuid
    set isofile="/isos/$iso_name"
    set iso_path="\$isofile"
    loopback loop (\$isopart)\$isofile
    configfile (loop)/boot/grub/loopback.cfg
}
CFG
        ok "Entrada GRUB: loopback.cfg nativo"
    else
        generate_grub_entry_fallback "$iso_name" "$distro" "$part_uuid" "$entry_file"
        warn "Entrada GRUB: modo genérico (sin loopback.cfg en la ISO)"
    fi
    ok "Entrada guardada: $(basename "$entry_file")"
}

generate_grub_entry_fallback() {
    local iso_name="$1" distro="$2" part_uuid="$3" entry_file="$4"
    local d="${distro,,}"
    local vmlinuz initrd params

    case "$d" in
        *ubuntu*|*mint*|*pop*|*zorin*|*elementary*|*kubuntu*|*xubuntu*|*lubuntu*)
            vmlinuz="/casper/vmlinuz"
            initrd="/casper/initrd"
            params="boot=casper iso-scan/filename=/isos/$iso_name quiet splash"
            ;;
        *debian*|*kali*|*parrot*|*mx*)
            vmlinuz="/live/vmlinuz"
            initrd="/live/initrd.img"
            params="boot=live findiso=/isos/$iso_name quiet splash"
            ;;
        *fedora*|*rocky*|*alma*|*centos*)
            vmlinuz="/isolinux/vmlinuz"
            initrd="/isolinux/initrd.img"
            params="root=live:UUID=$part_uuid rd.live.image quiet rhgb"
            ;;
        *arch*|*manjaro*)
            vmlinuz="/arch/boot/x86_64/vmlinuz-linux"
            initrd="/arch/boot/x86_64/initramfs-linux.img"
            params="archisobasedir=arch img_loop=/isos/$iso_name"
            ;;
        *opensuse*)
            vmlinuz="/boot/x86_64/loader/linux"
            initrd="/boot/x86_64/loader/initrd"
            params="isofrom=/isos/$iso_name splash=silent quiet"
            ;;
        *alpine*)
            vmlinuz="/boot/vmlinuz-lts"
            initrd="/boot/initramfs-lts"
            params="alpine_dev=UUID:$part_uuid iso-scan/filename=/isos/$iso_name"
            ;;
        *)
            vmlinuz="/casper/vmlinuz"
            initrd="/casper/initrd"
            params="boot=casper iso-scan/filename=/isos/$iso_name"
            ;;
    esac

    cat > "$entry_file" <<CFG
menuentry "$distro — $iso_name" --class linux {
    insmod part_gpt
    insmod part_msdos
    insmod ext2
    insmod loopback
    insmod iso9660
    search --no-floppy --fs-uuid --set=isopart $part_uuid
    set isofile="/isos/$iso_name"
    loopback loop (\$isopart)\$isofile
    linux  (loop)$vmlinuz $params
    initrd (loop)$initrd
}
CFG
}


# =============================================================================
# LISTAR ISOs
# =============================================================================

list_isos() {
    banner
    step "ISOs disponibles en MULTIBOOT"
    echo ""

    local count=0
    while IFS= read -r iso; do
        [[ -f "$iso" ]] || continue
        count=$((count + 1))
        local name sz entry grub_ok
        name=$(basename "$iso")
        sz=$(du -h "$iso" | cut -f1)
        entry="$ENTRIES_DIR/${name%.iso}.cfg"
        [[ -f "$entry" ]] && grub_ok="${G}en menú${N}" || grub_ok="${R}sin entrada GRUB${N}"
        printf "  ${C}%2d)${N}  %-52s  %6s  [%b]\n" "$count" "$name" "$sz" "$grub_ok"
    done < <(find "$ISO_DIR" -maxdepth 2 -name "*.iso" 2>/dev/null | sort)

    if [[ "$count" -eq 0 ]]; then
        echo -e "  ${Y}No hay ISOs cargadas todavía.${N}\n"
    else
        echo ""
        local avail
        avail=$(df -h "$MULTIBOOT_MOUNT" --output=avail | tail -1 | tr -d ' ')
        ok "Espacio libre en MULTIBOOT: ${W}$avail${N}"
    fi
    echo ""
}


# =============================================================================
# ELIMINAR ISO
# =============================================================================

remove_iso() {
    banner
    step "Eliminar una ISO"
    echo ""

    local -a isos
    while IFS= read -r iso; do
        [[ -f "$iso" ]] && isos+=("$iso")
    done < <(find "$ISO_DIR" -maxdepth 2 -name "*.iso" 2>/dev/null | sort)

    if [[ "${#isos[@]}" -eq 0 ]]; then
        echo -e "  No hay ISOs disponibles para eliminar.\n"
        pause; banner; detect_system; menu_principal; return
    fi

    local i=1
    for iso in "${isos[@]}"; do
        local sz; sz=$(du -h "$iso" | cut -f1)
        printf "  ${C}%2d)${N}  %-52s  %6s\n" "$i" "$(basename "$iso")" "$sz"
        i=$((i+1))
    done
    echo "   0)  Cancelar"
    echo ""

    local opt; opt=$(ask "¿Cuál eliminás? [0-${#isos[@]}]")

    [[ "$opt" == "0" ]] && { banner; detect_system; menu_principal; return; }

    if ! [[ "$opt" =~ ^[0-9]+$ ]] || \
       [[ "$opt" -lt 1 ]] || [[ "$opt" -gt "${#isos[@]}" ]]; then
        err "Opción inválida."; pause; remove_iso; return
    fi

    local target="${isos[$((opt-1))]}"
    local tname; tname=$(basename "$target")
    local entry="$ENTRIES_DIR/${tname%.iso}.cfg"

    echo ""
    warn "Vas a eliminar: ${W}$tname${N}"
    if ! confirm "¿Confirmar?"; then
        banner; detect_system; menu_principal; return
    fi

    rm -f "$target"
    [[ -f "$entry" ]] && rm -f "$entry"

    step "Actualizando GRUB..."; grub_update

    echo ""; ok "ISO eliminada: $tname"
    pause; banner; detect_system; menu_principal
}


# =============================================================================
# PUNTO DE ENTRADA
# =============================================================================

main() {
    if [[ "$EUID" -ne 0 ]]; then
        echo ""
        echo -e "  ${R}Error:${N} Este script necesita permisos de administrador."
        echo -e "  Ejecutalo con: ${W}sudo ./rm-multiboot.sh${N}\n"
        exit 1
    fi
    log_step "Inicio rm-multiboot.sh v${SCRIPT_VERSION}"
    log_info "Usuario: $(whoami) | PID: $$"
    log_info "Sistema: $(uname -sr) | Host: $(hostname)"
    banner
    detect_system
    menu_principal
}

main "$@"
