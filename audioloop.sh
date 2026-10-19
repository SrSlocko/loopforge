#!/usr/bin/env bash
# ============================================================================
#  AUDIOLOOP - Extended Audio/Video Generator for YouTube  v7.0
# ============================================================================
#  Extiende audios usando pymusiclooper y genera videos listos para YouTube
#  a partir de archivos, carpetas, archivos comprimidos, URLs o playlists.
#
#  Uso:
#    audioloop <input> <minutos> [imagen_portada] [output] [opciones]
#
#  Ejemplos:
#    audioloop cancion.mp3 60 cover.jpg
#    audioloop ./carpeta_musical 180 cover.jpg
#    audioloop playlist.zip 30 cover.jpg
#    audioloop "https://youtube.com/playlist?list=..." 60
#    audioloop a.mp3 60 cover.jpg , b.mp3 30 cover2.jpg
#
#  Opciones:
#    -tester      Procesa solo el primer archivo (modo prueba)
#    -shutdown N  Apaga el equipo N minutos después de terminar
#    --help       Muestra esta ayuda
#    --version    Muestra la versión
# ============================================================================

set -o pipefail

# ============================================================================
#  CONFIGURACIÓN POR DEFECTO
# ============================================================================
TEST_MODE=0
REMOVE_ORIGINAL=0
PARALLEL_JOBS=2
VIDEO_SIZE="1280x720"
VIDEO_FPS=25
VIDEO_CRF=30
AUDIO_BITRATE="128k"
MIN_AUDIO_SECS=15
VERSION="7.0"
HAS_IMAGEMAGICK=0
HAS_BC=0
HAS_JQ=0
HAS_UNRAR=0

# ============================================================================
#  COLORES Y SÍMBOLOS (con fallback si tput no existe)
# ============================================================================
if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
    declare -A COLORS=(
        [RED]=$(tput setaf 1)    [GREEN]=$(tput setaf 2)
        [YELLOW]=$(tput setaf 3) [BLUE]=$(tput setaf 4)
        [MAGENTA]=$(tput setaf 5) [CYAN]=$(tput setaf 6)
        [WHITE]=$(tput setaf 7)   [RESET]=$(tput sgr0)
    )
else
    declare -A COLORS=(
        [RED]='' [GREEN]='' [YELLOW]='' [BLUE]=''
        [MAGENTA]='' [CYAN]='' [WHITE]='' [RESET]=''
    )
fi

declare -A SYMBOLS=(
    [CHECK]="✓" [CROSS]="✗" [ARROW]="➤" [WARN]="⚠" [INFO]="ℹ"
)
SEP_LINE="════════════════════════════════════════════════════════════════"

# ============================================================================
#  FUNCIONES AUXILIARES
# ============================================================================

separator() { echo -e "${COLORS[BLUE]}${SEP_LINE}${COLORS[RESET]}"; }

log()   { echo -e "${1}${2}${COLORS[RESET]} $3"; }
error() {
    separator
    log "${COLORS[RED]}" "${SYMBOLS[CROSS]}" "ERROR: $1"
    separator
    exit 1
}
success() { echo -e "${COLORS[GREEN]}${SYMBOLS[CHECK]}${COLORS[RESET]} $1"; }
progress() { echo -e "${COLORS[CYAN]}${SYMBOLS[ARROW]}${COLORS[RESET]} $1" >&2; }
info() { echo -e "${COLORS[WHITE]}${SYMBOLS[INFO]}${COLORS[RESET]} $1"; }
warn() { echo -e "${COLORS[YELLOW]}${SYMBOLS[WARN]}${COLORS[RESET]} $1" >&2; }

header() {
    separator
    if (( TEST_MODE )); then
        echo -e "${COLORS[MAGENTA]}  ╔══════════════════════════════════╗
  ║   AUDIOLOOP TESTER v${VERSION}       ║
  ╚══════════════════════════════════╝${COLORS[RESET]}"
    else
        echo -e "${COLORS[MAGENTA]}  ╔══════════════════════════════════╗
  ║   AUDIOLOOP PRO v${VERSION}           ║
  ╚══════════════════════════════════╝${COLORS[RESET]}"
    fi
    separator
}

show_help() {
    cat <<EOF
${COLORS[MAGENTA]}AUDIOLOOP v${VERSION} - Generador de audio extendido para YouTube${COLORS[RESET}

${COLORS[CYAN]}DESCRIPCIÓN:${COLORS[RESET}
  Extiende audios automáticamente usando pymusiclooper y genera videos
  con imagen fija listos para subir a YouTube.

${COLORS[CYAN]}USO:${COLORS[RESET}
  audioloop <input> <minutos> [imagen_portada] [output] [opciones]

${COLORS[CYAN]}ENTRADAS SOPORTADAS:${COLORS[RESET}
  archivo.mp3          Audio individual
  ./carpeta/           Carpeta con audios
  archivo.zip/.rar     Archivo comprimido
  https://youtube.com  URL de video o playlist

${COLORS[CYAN]}EJEMPLOS:${COLORS[RESET}
  audioloop cancion.mp3 60 cover.jpg
  audioloop ./musica 180 cover.jpg
  audioloop album.zip 30 cover.jpg
  audioloop "https://youtube.com/playlist?list=XXX" 60
  audioloop a.mp3 60 cover.jpg , b.mp3 30 cover2.jpg

${COLORS[CYAN]}OPCIONES:${COLORS[RESET}
  -tester        Procesa solo el primer archivo (prueba rápida)
  -shutdown N    Apaga el PC N minutos después de terminar
  --help         Muestra esta ayuda
  --version      Muestra la versión

${COLORS[CYAN]}DEPENDENCIAS:${COLORS[RESET}
  Requeridas:  ffmpeg, ffprobe, yt-dlp, pymusiclooper
  Opcionales:  ImageMagick, unrar, jq

${COLORS[CYAN]}NOTAS:${COLORS[RESET}
  • Los audios < ${MIN_AUDIO_SECS}s se mueven a ~/Music/Sonidos_Cortos
  • Los archivos duplicados se eliminan automáticamente
  • Los videos se generan en resolución ${VIDEO_SIZE}
  • Soporta procesamiento paralelo (detecta CPU/RAM automáticamente)
EOF
    exit 0
}

show_version() {
    echo "audioloop v${VERSION}"
    exit 0
}

# ============================================================================
#  FUNCIONES DE SISTEMA
# ============================================================================

check_dependencies() {
    local required=("ffmpeg" "ffprobe" "yt-dlp" "pymusiclooper")
    local optional=("magick" "unrar" "bc" "jq")
    local missing=()

    for dep in "${required[@]}"; do
        command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
    done

    if [ ${#missing[@]} -ne 0 ]; then
        error "Dependencias faltantes: ${missing[*]}
  Instálalas con:
    Arch:   sudo pacman -S ffmpeg yt-dlp python-pymusiclooper imagemagick
    Debian: sudo apt install ffmpeg yt-dlp python3-pip
    pip:    pip install pymusiclooper
    macOS:  brew install ffmpeg yt-dlp imagemagick && pip install pymusiclooper"
    fi

    # Verificar opcionales
    command -v magick >/dev/null 2>&1 && HAS_IMAGEMAGICK=1
    command -v bc      >/dev/null 2>&1 && HAS_BC=1
    command -v jq      >/dev/null 2>&1 && HAS_JQ=1
    command -v unrar   >/dev/null 2>&1 && HAS_UNRAR=1

    # Fallback: convert (ImageMagick 6)
    if [ "$HAS_IMAGEMAGICK" -eq 0 ] && command -v convert >/dev/null 2>&1; then
        HAS_IMAGEMAGICK=2  # Usar convert en vez de magick
    fi

    if [ "$HAS_IMAGEMAGICK" -eq 0 ]; then
        warn "ImageMagick no encontrado. Usando ffmpeg para procesar imágenes."
    fi
}

detect_system_resources() {
    local cpu_cores ram_available
    cpu_cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
    ram_available=$(free -m 2>/dev/null | awk '/Mem:/ {print $7}' || echo 4096)

    # Ajustar trabajos paralelos
    if [ "$cpu_cores" -ge 4 ]; then
        PARALLEL_JOBS=$((cpu_cores / 2))
    else
        PARALLEL_JOBS=2
    fi

    # Reducir si poca RAM
    if [ "$ram_available" -lt 4096 ]; then
        PARALLEL_JOBS=$((PARALLEL_JOBS / 2))
        [ "$PARALLEL_JOBS" -lt 1 ] && PARALLEL_JOBS=1
    fi

    info "Sistema: ${cpu_cores} núcleos, ${ram_available} MB RAM libre → ${PARALLEL_JOBS} trabajos paralelos"
}

cleanup_tmp() {
    progress "Limpiando temporales antiguos..."
    rm -rf /tmp/videolooper.* /tmp/audioloop.* 2>/dev/null
}

# ============================================================================
#  FUNCIONES PARA NOMBRES DE ARCHIVO
# ============================================================================

clean_filename() {
    local name="$1"
    # Quitar sufijos _R/_L y extensión .dspadpcm (archivos de juegos)
    name=$(echo "$name" | sed -E 's/(_R|_L)$//' | sed -E 's/\.dspadpcm//g')
    # Normalizar patrones tipo "MUSIC 001", "Track 05", "bgm 3"
    if [[ "$name" =~ ^(MUSIC|Track|bgm|BGM|music)[[:space:]]+0*([0-9]+)$ ]]; then
        local prefix="${BASH_REMATCH[1]}"
        local number=$((10#${BASH_REMATCH[2]}))
        printf -v name "%s %02d" "$prefix" "$number"
    fi
    # Quitar números iniciales seguidos de espacio y letra
    name=$(echo "$name" | sed -E 's/^[0-9]+[[:space:]]*//')
    # Quitar paréntesis y su contenido
    name=$(echo "$name" | sed -E 's/\([^)]*\)//g; s/\.[^.]+$//g')
    # Reemplazar guiones y underscores por espacios
    name=$(echo "$name" | sed -E 's/[_-]+/ /g')
    # Colapsar espacios
    echo "$name" | xargs
}

clean_archive_name() {
    local name
    name=$(basename "$1")
    name="${name%.*}"
    name=$(echo "$name" | sed -E 's/\([^)]*\)//g; s/\.[^.]+$//g; s/[_-]+//g')
    echo "$name" | xargs
}

# ============================================================================
#  FUNCIONES DE IMAGEN
# ============================================================================

# Obtiene el color dominante de una imagen (para el pad del video)
get_dominant_color() {
    local image="$1" color
    if [ "$HAS_IMAGEMAGICK" -eq 1 ]; then
        color=$(magick "$image" -resize 1x1! -format "%[hex:u]" info: 2>/dev/null)
    elif [ "$HAS_IMAGEMAGICK" -eq 2 ]; then
        color=$(convert "$image" -resize 1x1! -format "%[hex:u]" info: 2>/dev/null)
    fi
    # Fallback con ffmpeg puro
    if [ -z "$color" ]; then
        color=$(ffmpeg -i "$image" -vf "scale=1:1" -frames:v 1 -f rawvideo -pix_fmt rgb24 - 2>/dev/null | xxd -p | head -c 6 | tr 'a-f' 'A-F')
    fi
    [ -z "$color" ] && color="000000"
    echo "$color"
}

# Preprocesa la imagen de portada: fondo difuminado + cover centrada
preprocess_cover() {
    local input="$1"
    local output bg blurred
    output=$(mktemp --suffix=.png 2>/dev/null || mktemp -t cover.png)

    if [ "$HAS_IMAGEMAGICK" -ge 1 ]; then
        local magick_cmd="magick"
        [ "$HAS_IMAGEMAGICK" -eq 2 ] && magick_cmd="convert"

        bg=$(mktemp --suffix=.png 2>/dev/null || mktemp -t bg.png)
        # Fondo: escalar a cubrir 1280x720 + blur
        if ! $magick_cmd "$input" -colorspace sRGB \
            -resize "${VIDEO_SIZE/x/}"'^' -gravity center \
            -extent "$VIDEO_SIZE" -blur 0x12 "$bg" 2>/dev/null; then
            rm -f "$bg"
            # Fallback a ffmpeg si magick falla
            HAS_IMAGEMAGICK=0
        fi

        if [ "$HAS_IMAGEMAGICK" -ge 1 ]; then
            # Cover: escalar a 600px de ancho
            blurred=$(mktemp --suffix=.png 2>/dev/null || mktemp -t fg.png)
            if ! $magick_cmd "$input" -colorspace sRGB -resize x600 "$blurred" 2>/dev/null; then
                rm -f "$bg" "$blurred"
                HAS_IMAGEMAGICK=0
            else
                # Componer: fondo difuminado + cover centrada
                if ! $magick_cmd "$bg" "$blurred" -gravity center \
                    -geometry +0+0 -composite "$output" 2>/dev/null; then
                    rm -f "$bg" "$blurred" "$output"
                    error "Error componiendo imagen final desde: $input"
                fi
                rm -f "$bg" "$blurred"
                if [ -f "$output" ] && [ -s "$output" ]; then
                    echo "$output"
                    return 0
                fi
            fi
        fi
    fi

    # Fallback: usar ffmpeg puro para procesar la imagen
    local w h
    w=${VIDEO_SIZE%x*}
    h=${VIDEO_SIZE#*x}

    # Crear fondo difuminado
    bg=$(mktemp --suffix=.png 2>/dev/null || mktemp -t bg.png)
    ffmpeg -hide_banner -loglevel error -y -i "$input" \
        -vf "scale=${w}:${h}:force_original_aspect_ratio=increase,crop=${w}:${h},boxblur=20:5" \
        "$bg" 2>/dev/null

    # Redimensionar cover
    blurred=$(mktemp --suffix=.png 2>/dev/null || mktemp -t fg.png)
    ffmpeg -hide_banner -loglevel error -y -i "$input" \
        -vf "scale=600:-1:force_original_aspect_ratio=decrease" \
        "$blurred" 2>/dev/null

    # Componer
    if [ -f "$bg" ] && [ -f "$blurred" ]; then
        ffmpeg -hide_banner -loglevel error -y \
            -i "$bg" -i "$blurred" \
            -filter_complex "[0][1]overlay=(W-w)/2:(H-h)/2" \
            "$output" 2>/dev/null
    fi

    rm -f "$bg" "$blurred"

    if [ -f "$output" ] && [ -s "$output" ]; then
        echo "$output"
    else
        # Si todo falla, usar la imagen original
        echo "$input"
    fi
}

# ============================================================================
#  FUNCIONES DE AUDIO
# ============================================================================

# Filtra audios muy cortos y los mueve a una carpeta
filter_short_audios() {
    local dir="$1" dest="$HOME/Music/Sonidos_Cortos"
    mkdir -p "$dest"
    progress "Filtrando audios < ${MIN_AUDIO_SECS}s en: $dir"
    find "$dir" -type f \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.m4a" \) 2>/dev/null | while read -r file; do
        local duration parent base
        duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | cut -d. -f1)
        if [[ -n "$duration" && "$duration" -le "$MIN_AUDIO_SECS" ]]; then
            parent=$(basename "$(dirname "$file")")
            base=$(basename "$file")
            progress "  Moviendo corto: ${base} (${duration}s)"
            mv -n "$file" "$dest/${parent}_${base}" 2>/dev/null
        fi
    done
}

# Elimina archivos duplicados por hash MD5
remove_duplicates() {
    local -n files_array=$1
    local unique_files=()
    declare -A hash_map

    for file in "${files_array[@]}"; do
        if [ -f "$file" ]; then
            local hash
            hash=$(md5sum "$file" 2>/dev/null | awk '{print $1}')
            if [ -n "$hash" ] && [ -z "${hash_map[$hash]:-}" ]; then
                hash_map[$hash]="$file"
                unique_files+=("$file")
            elif [ -n "$hash" ]; then
                progress "  Duplicado eliminado: $(basename "$file")"
            else
                unique_files+=("$file")
            fi
        fi
    done

    local removed=$(( ${#files_array[@]} - ${#unique_files[@]} ))
    [ "$removed" -gt 0 ] && info "Archivos duplicados eliminados: $removed"

    files_array=("${unique_files[@]}")
}

# Extiende un audio usando pymusiclooper
process_audio() {
    local input="$1" target_secs="$2" output="$3"
    local temp_dir temp_wav

    temp_dir=$(mktemp -d /tmp/audioloop.XXXXXX 2>/dev/null || mktemp -d -t audioloop.XXXXXX)
    temp_wav="${temp_dir}/audio.wav"

    # Convertir a WAV para análisis
    if ! ffmpeg -hide_banner -loglevel error -y -i "$input" -c:a pcm_s16le "$temp_wav" 2>/dev/null; then
        rm -rf "$temp_dir"
        warn "Error convirtiendo: $(basename "$input")"
        return 1
    fi

    # Intentar extender con pymusiclooper
    if ! pymusiclooper extend --path "$temp_wav" \
        --extended-length "$target_secs" --format MP3 \
        --output-dir "$temp_dir" >/dev/null 2>&1; then

        # Reintentar con parámetros ajustados
        if ! pymusiclooper extend --path "$temp_wav" \
            --extended-length "$target_secs" --format MP3 \
            --output-dir "$temp_dir" --min-duration 10 --max-duration 60 >/dev/null 2>&1; then

            rm -rf "$temp_dir"
            warn "Sin loop points para: $(basename "$input")"
            [ "$REMOVE_ORIGINAL" -eq 1 ] && rm -f "$input"
            return 1
        fi
    fi

    # Buscar el archivo extendido generado
    local extended_audio
    extended_audio=$(find "$temp_dir" -name '*extended*.mp3' -print -quit 2>/dev/null)
    if [ -z "$extended_audio" ]; then
        rm -rf "$temp_dir"
        warn "No se generó audio extendido: $(basename "$input")"
        [ "$REMOVE_ORIGINAL" -eq 1 ] && rm -f "$input"
        return 1
    fi

    # Mover al destino
    mkdir -p "$(dirname "$output")"
    if ! mv "$extended_audio" "$output" 2>/dev/null; then
        rm -rf "$temp_dir"
        warn "Error moviendo audio extendido: $(basename "$input")"
        return 1
    fi

    rm -rf "$temp_dir"
    [ "$REMOVE_ORIGINAL" -eq 1 ] && rm -f "$input"
    return 0
}

# ============================================================================
#  FUNCIONES DE VIDEO
# ============================================================================

generate_video() {
    local image="$1" audio="$2" output="$3"
    [ ! -f "$image" ] && error "Imagen no encontrada: $image"

    local processed_image duration color ffmpeg_pid start_time elapsed
    local w h
    w=${VIDEO_SIZE%x*}
    h=${VIDEO_SIZE#*x}

    # Preprocesar portada
    processed_image=$(preprocess_cover "$image")
    if [ ! -f "$processed_image" ]; then
        error "No se pudo procesar la imagen de portada."
    fi

    # Obtener duración del audio
    duration=$(ffprobe -v error -select_streams a:0 \
        -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 \
        "$audio" 2>/dev/null)
    if [ -z "$duration" ] || ! awk "BEGIN {exit !($duration > 0)}" 2>/dev/null; then
        duration=1
    fi

    # Obtener color dominante para el pad
    color=$(get_dominant_color "$processed_image")

    # Generar video
    start_time=$(date +%s)
    ffmpeg -hide_banner -loglevel error -nostdin -y \
        -loop 1 -framerate 1 -i "$processed_image" -i "$audio" \
        -vf "scale=${w}:${h}:force_original_aspect_ratio=decrease:flags=neighbor,
             pad=${w}:${h}:(ow-iw)/2:(oh-ih)/2:color=0x${color},
             format=yuv420p,fps=${VIDEO_FPS}" \
        -c:v libx264 -preset ultrafast -crf ${VIDEO_CRF} -tune stillimage \
        -g 250 -x264-params keyint=250:min-keyint=25:no-scenecut=1 \
        -pix_fmt yuv420p \
        -c:a aac -b:a ${AUDIO_BITRATE} -shortest \
        -movflags +faststart \
        -t "$duration" \
        "$output" 2>/dev/null &
    ffmpeg_pid=$!

    # Spinner mientras renderiza
    local spinner=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' ) i=0
    printf "${COLORS[YELLOW]}  Renderizando: %s " "$(basename "$output")" >&2
    while kill -0 "$ffmpeg_pid" 2>/dev/null; do
        printf "\r${COLORS[YELLOW]}  Renderizando: %s %s" "$(basename "$output")" "${spinner[i]}" >&2
        i=$(( (i + 1) % 10 ))
        sleep 0.1
    done
    wait "$ffmpeg_pid"
    local exit_code=$?
    elapsed=$(( $(date +%s) - start_time ))

    rm -f "$audio" "$processed_image"

    if [ "$exit_code" -eq 0 ] && [ -f "$output" ]; then
        printf "\r${COLORS[YELLOW]}  Renderizando: %s ${COLORS[GREEN]}✓${COLORS[RESET]} (%ss)\n" "$(basename "$output")" "$elapsed" >&2
        if (( TEST_MODE )); then
            local size
            size=$(stat -c %s "$output" 2>/dev/null || stat -f %z "$output" 2>/dev/null || echo "?")
            echo "  Tiempo: ${elapsed}s | Tamaño: ${size} bytes | Duración: ${duration}s" > "$(dirname "$output")/reporte.txt"
        fi
        return 0
    else
        printf "\r${COLORS[RED]}  Error generando: %s${COLORS[RESET}\n" "$(basename "$output")" >&2
        return 1
    fi
}

# Mueve los videos generados a una subcarpeta
group_videos() {
    local output_dir="$1"
    local video_dir="${output_dir}/videos"

    mkdir -p "$video_dir" 2>/dev/null || return 1

    local count=0
    while IFS= read -r -d '' video; do
        mv "$video" "$video_dir/" 2>/dev/null && count=$((count + 1))
    done < <(find "$output_dir" -maxdepth 1 -type f -iname "*.mp4" -print0 2>/dev/null)

    [ "$count" -gt 0 ] && info "Videos organizados en: $video_dir"
}

# ============================================================================
#  FUNCIONES DE PROCESAMIENTO
# ============================================================================

# Procesa un solo archivo de audio → extiende → genera video
process_file() {
    local file="$1" dir="$2" target_secs="$3" cover_image="$4" output_dir="$5" index="$6" total="$7"
    local relative_path base cleaned extended_file video_output

    relative_path="${file#$dir/}"
    base="${relative_path%.*}"
    cleaned=$(clean_filename "$base")

    # Archivo temporal para el audio extendido
    local tmp_audio_dir
    tmp_audio_dir=$(mktemp -d /tmp/audioloop.XXXXXX 2>/dev/null || mktemp -d -t audioloop.XXXXXX)
    extended_file="${tmp_audio_dir}/${cleaned}_extended.mp3"

    progress "[$index/$total] Procesando: $relative_path"

    if ! process_audio "$file" "$target_secs" "$extended_file"; then
        rm -rf "$tmp_audio_dir"
        return 1
    fi

    video_output="${output_dir}/${cleaned}.mp4"
    generate_video "$cover_image" "$extended_file" "$video_output"
    local result=$?
    rm -rf "$tmp_audio_dir"
    return $result
}

# Procesa un directorio completo
process_dir() {
    local dir="$1" target_secs="$2" cover_image="$3" remove_orig="${4:-0}"

    filter_short_audios "$dir"

    local suffix="_extended"
    (( TEST_MODE )) && suffix="_tester"
    local output_dir="${dir}${suffix}"
    mkdir -p "$output_dir" || error "Error creando directorio de salida."

    progress "Buscando audios en: $dir"
    local audio_files=()
    while IFS= read -r -d '' file; do
        audio_files+=("$file")
    done < <(find "$dir" -type f \( -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.m4a" \) -print0 2>/dev/null)

    if [ ${#audio_files[@]} -eq 0 ]; then
        warn "No se encontraron archivos de audio en: $dir"
        return 1
    fi

    remove_duplicates audio_files

    local total=${#audio_files[@]} i=0 job_count=0
    info "Archivos a procesar: $total | Paralelismo: $PARALLEL_JOBS"

    for file in "${audio_files[@]}"; do
        i=$(( i + 1 ))
        process_file "$file" "$dir" "$target_secs" "$cover_image" "$output_dir" "$i" "$total" &
        job_count=$(( job_count + 1 ))
        if (( job_count >= PARALLEL_JOBS )); then
            wait -n 2>/dev/null || wait
            job_count=$(( job_count - 1 ))
        fi
        (( TEST_MODE )) && { wait; break; }
    done
    wait

    group_videos "$output_dir"
    (( remove_orig )) && rm -f "$file"
}

# Procesa un archivo comprimido (zip/rar)
process_archive() {
    local archive="$1" target_secs="$2" cover_image="$3"
    local base_name extract_dir suffix
    base_name=$(clean_archive_name "$archive")
    extract_dir="./${base_name}"

    [ -d "$extract_dir" ] && rm -rf "$extract_dir"
    mkdir -p "$extract_dir" || error "Error creando carpeta de extracción."

    if [[ "$archive" =~ \.zip$ ]]; then
        progress "Extrayendo ZIP: $archive"
        unzip -q "$archive" -d "$extract_dir" || error "Error extrayendo ZIP."
    elif [[ "$archive" =~ \.rar$ ]]; then
        [ "$HAS_UNRAR" -eq 0 ] && error "Instala 'unrar' para archivos RAR."
        progress "Extrayendo RAR: $archive"
        unrar x -o+ "$archive" "$extract_dir" >/dev/null || error "Error extrayendo RAR."
    else
        error "Formato no soportado. Usa .zip o .rar"
    fi

    # Procesar los archivos extraídos (elimina originales)
    REMOVE_ORIGINAL=1
    process_dir "$extract_dir" "$target_secs" "$cover_image" 1
    REMOVE_ORIGINAL=0

    (( TEST_MODE )) && suffix="tester" || suffix="extended"
    mv "$extract_dir" "./${base_name}_${suffix}" 2>/dev/null
    group_videos "./${base_name}_${suffix}"
    success "Procesado: ./${base_name}_${suffix}"
}

# Descarga un frame del video como portada por defecto
get_default_cover() {
    local url="$1" temp_dir="$2"
    local cover_output="${temp_dir}/default_cover.jpg"

    progress "Extrayendo frame del video para usar como portada..."
    local temp_video="${temp_dir}/temp_video.mp4"
    yt-dlp -o "$temp_video" --quiet --merge-output-format mp4 --no-playlist "$url" 2>/dev/null || {
        error "No se pudo descargar el video para extraer el frame."
    }
    ffmpeg -hide_banner -loglevel error -y -i "$temp_video" -frames:v 1 -q:v 2 "$cover_output" 2>/dev/null || {
        error "No se pudo extraer el frame del video."
    }
    [ -s "$cover_output" ] && echo "$cover_output" || error "Frame de portada inválido."
}

# Procesa una URL (video individual o playlist de YouTube)
process_url() {
    local url="$1" target_secs="$2" cover_image="$3"
    local temp_dir output_dir extended_dir

    temp_dir=$(mktemp -d /tmp/audioloop.XXXXXX 2>/dev/null || mktemp -d -t audioloop.XXXXXX)

    # Obtener título de la playlist
    local playlist_title
    playlist_title=$(yt-dlp --get-title --no-playlist "$url" 2>/dev/null | head -n 1)
    [ -z "$playlist_title" ] && playlist_title="playlist_$(date +%s)"
    playlist_title=$(echo "$playlist_title" | sed 's/[^a-zA-Z0-9 -]//g' | cut -c 1-50 | xargs)

    output_dir="$(pwd)/${playlist_title}"
    extended_dir="$(pwd)/${playlist_title}_extended"
    mkdir -p "$output_dir" "$extended_dir" || error "Error creando directorios de salida."

    # Contar canciones de la playlist
    local total_videos
    if [ "$HAS_JQ" -eq 1 ]; then
        total_videos=$(yt-dlp --flat-playlist --dump-json "$url" 2>/dev/null | jq -s 'length')
    else
        total_videos=$(yt-dlp --flat-playlist --dump-json "$url" 2>/dev/null | grep -c '"id"')
    fi
    [ -z "$total_videos" ] || [ "$total_videos" -eq 0 ] && total_videos="?"
    info "Canciones en la lista: $total_videos"

    # Descargar audios como MP3
    progress "Descargando audios..."
    yt-dlp -x --audio-format mp3 \
        --output "${output_dir}/%(playlist_index)s - %(title)s.%(ext)s" \
        --no-progress --quiet "$url" || {
        rm -rf "$temp_dir"
        error "Error descargando audios desde la URL."
    }

    # Recopilar audios descargados
    local audio_files=()
    while IFS= read -r -d '' file; do
        audio_files+=("$file")
    done < <(find "$output_dir" -type f -iname "*.mp3" -print0 2>/dev/null)

    [ ${#audio_files[@]} -eq 0 ] && { rm -rf "$temp_dir"; error "No se encontraron audios descargados."; }

    local total=${#audio_files[@]} index=1 job_count=0
    info "Procesando $total audios | Paralelismo: $PARALLEL_JOBS"

    for audio_file in "${audio_files[@]}"; do
        local base_name clean_name extended_audio video_output
        base_name=$(basename "$audio_file" .mp3)
        clean_name=$(echo "$base_name" | sed 's/[^a-zA-Z0-9 -]//g' | xargs)

        extended_audio="${temp_dir}/${clean_name}_extended.mp3"
        video_output="${extended_dir}/${clean_name}.mp4"

        progress "[$index/$total] Procesando: ${clean_name}"

        if process_audio "$audio_file" "$target_secs" "$extended_audio"; then
            generate_video "$cover_image" "$extended_audio" "$video_output" &
            job_count=$(( job_count + 1 ))
            if (( job_count >= PARALLEL_JOBS )); then
                wait -n 2>/dev/null || wait
                job_count=$(( job_count - 1 ))
            fi
        fi
        index=$((index + 1))
    done
    wait

    group_videos "$extended_dir"
    rm -rf "$temp_dir"
    success "Videos generados en: $extended_dir"
}

# ============================================================================
#  APAGADO PROGRAMADO
# ============================================================================

is_within_shutdown_window() {
    local hour minute now
    hour=$(date +%H); minute=$(date +%M)
    now=$((10#$hour * 60 + 10#$minute))
    [ "$now" -ge 1 ] && [ "$now" -le 420 ]  # 00:01 - 07:00
}

schedule_shutdown() {
    local minutes="$1"
    if is_within_shutdown_window; then
        echo -e "${COLORS[YELLOW]}  ¿Apagar el equipo en ${minutes} minutos? (s/n) [30s]${COLORS[RESET]}" >&2
        local response
        read -t 30 -n 1 -r response
        if [[ "$response" =~ ^[Ss]$ ]]; then
            info "Apagado programado en ${minutes} minutos."
            shutdown -h +"$minutes" 2>/dev/null || sudo shutdown -h +"$minutes" 2>/dev/null
        else
            info "Apagado cancelado."
        fi
    else
        info "Fuera del horario de apagado (00:01-07:00). No se programa apagado."
    fi
}

# ============================================================================
#  PROCESAMIENTO DE GRUPOS (múltiples entradas separadas por coma)
# ============================================================================

process_group() {
    local group_str="$1"
    # Separar por ||
    local args=()
    IFS='|' read -ra raw_args <<< "$group_str"
    # Filtrar strings vacíos
    for a in "${raw_args[@]}"; do
        [ -n "$a" ] && args+=("$a")
    done

    [ ${#args[@]} -lt 2 ] && error "Grupo inválido: se necesitan al menos input y minutos."

    local input target_secs cover_image output
    input="${args[0]}"

    # Resolver input
    if [[ "$input" == http* ]]; then
        :  # URL, dejar como está
    else
        input=$(realpath "$input" 2>/dev/null)
        [ ! -e "$input" ] && error "No existe: $input"
    fi

    # Calcular duración objetivo
    local minutes="${args[1]}"
    if [ "$minutes" -eq 30 ]; then
        target_secs="1799.232"
    else
        target_secs=$(awk "BEGIN {printf \"%.3f\", ${minutes}*60}")
    fi

    # Portada
    local temp_cover_dir=""
    if [ ${#args[@]} -ge 3 ] && [ -n "${args[2]}" ]; then
        cover_image=$(realpath "${args[2]}" 2>/dev/null)
        [ ! -f "$cover_image" ] && error "Imagen no encontrada: ${args[2]}"
    else
        if [[ "$input" == http* ]]; then
            temp_cover_dir=$(mktemp -d /tmp/audioloop.XXXXXX 2>/dev/null || mktemp -d -t audioloop.XXXXXX)
            cover_image=$(get_default_cover "$input" "$temp_cover_dir")
        else
            error "Se requiere imagen de portada para entradas locales."
        fi
    fi

    [ ${#args[@]} -ge 4 ] && output="${args[3]}"

    # Procesar
    local start_time elapsed
    start_time=$(date +%s)

    if [[ "$input" == http* ]]; then
        process_url "$input" "$target_secs" "$cover_image"
    elif [[ -d "$input" ]]; then
        process_dir "$input" "$target_secs" "$cover_image" 0
        output="${input}_extended"
    elif [[ "$input" =~ \.(zip|rar)$ ]]; then
        process_archive "$input" "$target_secs" "$cover_image"
        output="${input}_extended"
    elif [[ -f "$input" ]]; then
        [ -z "$output" ] && output="${input%.*}_extended.mp4"
        local tmp_audio
        tmp_audio=$(mktemp --suffix=.mp3 2>/dev/null || mktemp -t audio.mp3)
        progress "Extendiendo audio..."
        if ! process_audio "$input" "$target_secs" "$tmp_audio"; then
            error "No se pudo extender: $(basename "$input")"
        fi
        progress "Generando video..."
        local base cleaned
        base=$(basename "${input%.*}")
        cleaned=$(clean_filename "$base")
        output="$(dirname "$input")/${cleaned}.mp4"
        generate_video "$cover_image" "$tmp_audio" "$output"
    else
        error "Entrada no válida: $input"
    fi

    # Limpiar portada temporal
    [ -n "$temp_cover_dir" ] && rm -rf "$temp_cover_dir"

    elapsed=$(( $(date +%s) - start_time ))
    separator
    echo -e "${COLORS[GREEN]}  Resumen:${COLORS[RESET}"
    echo -e "    Estado:   ${COLORS[GREEN]}✓ Completado${COLORS[RESET}"
    echo -e "    Tiempo:   ${elapsed} segundos"
    echo -e "    Salida:   ${output:-${input}_extended}"
    separator
}

# ============================================================================
#  FUNCIÓN PRINCIPAL
# ============================================================================

main() {
    # Flags de línea de comandos
    for arg in "$@"; do
        case "$arg" in
            --help)    show_help ;;
            --version) show_version ;;
        esac
    done

    header
    check_dependencies
    detect_system_resources
    cleanup_tmp

    # Parsear flags
    local shutdown_minutes=""
    if [[ "${@: -1}" == "-tester" ]]; then
        TEST_MODE=1
        set -- "${@:1:$(($#-1))}"
        progress "Modo tester activado (solo primer archivo)"
    fi
    if [[ "${@: -2:1}" == "-shutdown" ]]; then
        shutdown_minutes="${@: -1}"
        set -- "${@:1:$(($#-2))}"
    fi

    [ $# -lt 2 ] && error "Uso: $0 <input> <minutos> [imagen] [output] [opciones]
  Usa --help para más información."

    # Agrupar argumentos por coma
    local groups=() current_group=()
    for arg in "$@"; do
        if [ "$arg" = "," ]; then
            groups+=("$(IFS='|'; echo "${current_group[*]}")")
            current_group=()
        else
            current_group+=("$arg")
        fi
    done
    [ ${#current_group[@]} -gt 0 ] && groups+=("$(IFS='|'; echo "${current_group[*]}")")

    # Procesar cada grupo
    local total_groups=${#groups[@]} group_num=0
    for group in "${groups[@]}"; do
        group_num=$((group_num + 1))
        (( total_groups > 1 )) && info "Procesando grupo $group_num/$total_groups"
        process_group "$group"
    done

    # Apagado programado
    [ -n "$shutdown_minutes" ] && schedule_shutdown "$shutdown_minutes"

    cleanup_tmp
    success "¡Todo completado!"
}

# Ejecutar solo si se invoca directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
