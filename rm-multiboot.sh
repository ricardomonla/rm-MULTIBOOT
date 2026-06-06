#!/usr/bin/env bash
# =============================================================================
#  rm-multiboot.sh — Gestor de Multiboot desde disco interno
# =============================================================================
#  Autor:    Lic. Ricardo MONLA
#  Email:    rmonla@gmail.com
#  GitHub:   https://github.com/ricardomonla/rm-MULTIBOOT
#  Versión:  2.1.0
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
readonly SCRIPT_VERSION="2.1.0"
readonly SCRIPT_AUTHOR="Lic. Ricardo MONLA"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ISOS_CONF="$SCRIPT_DIR/isos.conf"
readonly ISOS_CONF_URL="https://raw.githubusercontent.com/ricardomonla/rm-MULTIBOOT/main/isos.conf"

readonly MULTIBOOT_LABEL="MULTIBOOT"
readonly MULTIBOOT_MOUNT="/mnt/multiboot"
readonly ISO_DIR="$MULTIBOOT_MOUNT/isos"
readonly ENTRIES_DIR="$MULTIBOOT_MOUNT/grub/entries"
readonly GRUB_HOOK="/etc/grub.d/41_multiboot"

# ─── Colores ──────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
B='\033[0;34m' C='\033[0;36m' W='\033[1m' N='\033[0m'

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

ok()      { echo -e "  ${G}✓${N}  $*"; }
warn()    { echo -e "  ${Y}⚠${N}  $*"; }
err()     { echo -e "  ${R}✗${N}  $*"; }
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

setup_wizard() {
    banner
    step "Asistente de configuración inicial"
    echo ""

    local free_raw
    free_raw=$(parted -s "$ROOT_DISK_DEV" unit MiB print free 2>/dev/null \
               | awk '/Free Space/ && $3+0 >= 10240 {print $1, $2, $3}')

    if [[ -z "$free_raw" ]]; then
        err "No se encontró espacio libre ≥ 10 GB sin asignar en $ROOT_DISK_DEV"
        echo -e "\n  Para continuar necesitás liberar espacio con GParted u otra herramienta.\n"
        pause; exit 1
    fi

    echo -e "  Espacio libre sin asignar en ${W}$ROOT_DISK_DEV${N}:\n"
    local -a starts ends sizes
    local i=1
    while read -r start end size; do
        local size_gib
        size_gib=$(echo "$size" | sed 's/MiB//' | awk '{printf "%.0f", $1/1024}')
        starts+=("$start"); ends+=("$end"); sizes+=("$size_gib")
        printf "    ${C}%d)${N}  %s GB libres  (desde %s hasta %s)\n" \
            "$i" "$size_gib" "$start" "$end"
        i=$((i+1))
    done <<< "$free_raw"
    echo ""

    local region_opt=1
    if [[ "${#starts[@]}" -gt 1 ]]; then
        region_opt=$(ask "¿En qué región crear la partición?" "1")
        if ! [[ "$region_opt" =~ ^[0-9]+$ ]] || \
           [[ "$region_opt" -lt 1 ]] || [[ "$region_opt" -gt "${#starts[@]}" ]]; then
            err "Opción inválida."; pause; setup_wizard; return
        fi
    fi

    local idx=$((region_opt - 1))
    local free_start="${starts[$idx]}"
    local max_gib="${sizes[$idx]}"
    local recommended=$((max_gib > 100 ? 50 : max_gib))

    echo -e "  ${Y}Nota:${N} cada ISO pesa entre 600 MB y 5 GB."
    echo -e "  Recomendado: ≥ 30 GB para tener varias ISOs.\n"
    local size_gb
    size_gb=$(ask "¿Cuántos GB asignar a MULTIBOOT? (máx $max_gib)" "$recommended")

    if ! [[ "$size_gb" =~ ^[0-9]+$ ]] || \
       [[ "$size_gb" -lt 10 ]] || [[ "$size_gb" -gt "$max_gib" ]]; then
        err "Tamaño inválido. Debe ser un número entre 10 y $max_gib."; pause
        setup_wizard; return
    fi

    local start_mib end_mib
    start_mib=$(echo "$free_start" | sed 's/MiB//')
    end_mib=$((start_mib + size_gb * 1024))

    echo ""
    echo -e "  ${W}Resumen:${N}"
    echo -e "    Disco:          $ROOT_DISK_DEV"
    echo -e "    Tamaño:         ${size_gb} GB"
    echo -e "    Etiqueta:       $MULTIBOOT_LABEL"
    echo -e "    Sistema de arch: ext4"
    echo -e "    Punto de montaje: $MULTIBOOT_MOUNT"
    echo ""

    if ! confirm "¿Crear la partición ahora?"; then
        echo ""; warn "Operación cancelada."; pause; exit 0
    fi

    echo ""
    step "Creando partición..."

    local parts_before
    parts_before=$(lsblk -lno NAME "$ROOT_DISK_DEV" \
                   | grep -v "^$(basename "$ROOT_DISK_DEV")$" | sort)

    local part_table
    part_table=$(parted -s "$ROOT_DISK_DEV" print 2>/dev/null \
                 | awk '/Partition Table/{print $3}')

    if [[ "$part_table" == "gpt" ]]; then
        parted -s "$ROOT_DISK_DEV" mkpart "$MULTIBOOT_LABEL" ext4 \
            "${start_mib}MiB" "${end_mib}MiB" 2>/dev/null
    else
        parted -s "$ROOT_DISK_DEV" mkpart primary ext4 \
            "${start_mib}MiB" "${end_mib}MiB" 2>/dev/null
    fi

    sleep 1; partprobe "$ROOT_DISK_DEV" 2>/dev/null || true; sleep 1

    local new_part
    new_part=$(comm -13 \
        <(echo "$parts_before") \
        <(lsblk -lno NAME "$ROOT_DISK_DEV" \
          | grep -v "^$(basename "$ROOT_DISK_DEV")$" | sort) \
        | head -1)

    if [[ -z "$new_part" ]]; then
        err "No se pudo identificar la nueva partición. Revisá con 'lsblk'."
        pause; exit 1
    fi
    MULTIBOOT_DEV="/dev/$new_part"
    ok "Partición creada: $MULTIBOOT_DEV"

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
    local iso_filename
    iso_filename=$(basename "${chosen_url%%\?*}")
    local dest="$ISO_DIR/$iso_filename"

    echo ""
    echo -e "  ${W}ISO seleccionada:${N}"
    ok "Nombre:  ${W}$chosen_name${N}"
    ok "Archivo: $iso_filename"
    ok "URL:     ${C}$chosen_url${N}"
    echo ""

    # Verificar si ya existe
    if [[ -f "$dest" ]]; then
        warn "Esta ISO ya está descargada en la partición MULTIBOOT."
        if ! confirm "¿Descargar de nuevo y sobreescribir?"; then
            banner; detect_system; menu_principal; return
        fi
    fi

    # Verificar espacio (estimamos con el tamaño del Content-Length del servidor)
    local avail_k
    avail_k=$(df "$MULTIBOOT_MOUNT" --output=avail | tail -1)
    echo -e "  Espacio libre en MULTIBOOT: $(( avail_k / 1024 / 1024 )) GB\n"

    if ! confirm "¿Iniciar descarga?"; then
        banner; detect_system; menu_principal; return
    fi

    # Descargar
    echo ""
    step "Descargando $iso_filename..."
    echo ""

    if command -v wget &>/dev/null; then
        wget --show-progress -q -c -O "$dest" "$chosen_url" \
            || { err "Falló la descarga."; rm -f "$dest"; pause
                 banner; detect_system; menu_principal; return; }
    elif command -v curl &>/dev/null; then
        curl -L -C - --progress-bar -o "$dest" "$chosen_url" \
            || { err "Falló la descarga."; rm -f "$dest"; pause
                 banner; detect_system; menu_principal; return; }
    else
        err "No se encontró wget ni curl. Instalá uno de los dos e intentá de nuevo."
        pause; banner; detect_system; menu_principal; return
    fi

    echo ""
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
    banner
    detect_system
    menu_principal
}

main "$@"
