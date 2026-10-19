# 🎵 Audioloop

**Generador de audio extendido para YouTube** — Extiende canciones y crea videos listos para subir, todo desde la terminal.

[![Bash](https://img.shields.io/badge/Bash-5.0+-blue?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![ffmpeg](https://img.shields.io/badge/ffmpeg-required-green)](https://ffmpeg.org/)
[![License](https://img.shields.io/badge/license-MIT-yellow)](LICENSE)

---

## ✨ ¿Qué hace?

Audioloop toma tus audios y los **extiende automáticamente** usando detección de loop points (pymusiclooper), luego genera un **video con imagen fija** listo para subir a YouTube. Sin edición manual.

```
cancion.mp3  →  [detección de loop]  →  cancion_extendida.mp3  →  🎬 cancion.mp4
```

### Flujo automático

| Paso | Qué pasa |
|------|----------|
| 1 | Detecta el sistema (CPU, RAM) y ajusta trabajos paralelos |
| 2 | Filtra audios < 15s y elimina duplicados |
| 3 | Extiende cada audio con pymusiclooper |
| 4 | Preprocesa la imagen de portada (fondo difuminado + cover) |
| 5 | Renderiza el video en 1280×720 con ffmpeg |
| 6 | Organiza los videos en carpetas |

---

## 🚀 Instalación

### Arch Linux
```bash
sudo pacman -S ffmpeg yt-dlp imagemagick python-pymusiclooper
# Alternativa si no está en repos:
pip install pymusiclooper
```

### Ubuntu / Debian
```bash
sudo apt install ffmpeg yt-dlp imagemagick python3-pip
pip install pymusiclooper
```

### macOS
```bash
brew install ffmpeg yt-dlp imagemagick
pip install pymusiclooper
```

### Extras opcionales
```bash
# Para archivos .rar
sudo pacman -S unrar        # Arch
sudo apt install unrar      # Debian

# Para contar playlists más rápido
sudo pacman -S jq           # Arch
sudo apt install jq         # Debian
```

---

## 📖 Uso

### Básico
```bash
# Extender una canción 60 minutos con imagen de portada
./audioloop.sh cancion.mp3 60 cover.jpg

# Extender todos los audios de una carpeta 3 horas
./audioloop.sh ./mi_carpeta 180 cover.jpg

# Procesar un archivo comprimido
./audioloop.sh album.zip 30 cover.jpg
```

### Playlists de YouTube
```bash
# Descargar playlist, extender cada canción y generar videos
./audioloop.sh "https://youtube.com/playlist?list=XXXXX" 60 cover.jpg
```

### Múltiples entradas
```bash
# Procesar varios archivos en una sola ejecución (separados por coma)
./audioloop.sh cancion1.mp3 60 cover1.jpg , cancion2.mp3 30 cover2.jpg
```

### Opciones
```bash
./audioloop.sh cancion.mp3 60 cover.jpg -tester      # Solo primer archivo (prueba)
./audioloop.sh cancion.mp3 60 cover.jpg -shutdown 30  # Apagar 30 min después
./audioloop.sh --help                                 # Ayuda completa
./audioloop.sh --version                              # Versión
```

---

## 📁 Entradas soportadas

| Tipo | Ejemplo | Descripción |
|------|---------|-------------|
| Archivo de audio | `cancion.mp3` | MP3, WAV, FLAC, OGG, M4A |
| Carpeta | `./musica/` | Procesa todos los audios dentro |
| ZIP | `album.zip` | Extrae y procesa todo |
| RAR | `album.rar` | Extrae y procesa todo (requiere unrar) |
| Video URL | `https://youtube.com/watch?v=...` | Descarga audio y genera video |
| Playlist URL | `https://youtube.com/playlist?list=...` | Descarga y procesa toda la lista |

---

## ⚙️ Configuración

Edita las variables al inicio del script:

```bash
VIDEO_SIZE="1280x720"    # Resolución del video
VIDEO_FPS=25             # FPS del video
VIDEO_CRF=30             # Calidad (menor = mejor, 18-28 recomendado)
AUDIO_BITRATE="128k"     # Bitrate de audio
MIN_AUDIO_SECS=15        # Audios más cortos se filtran
```

---

## 🖥️ Requisitos

**Requeridos:**
- `ffmpeg` + `ffprobe` — procesamiento de audio/video
- `yt-dlp` — descarga de URLs y playlists
- `pymusiclooper` — detección de loop points

**Opcionales:**
- `ImageMagick` — mejor procesamiento de portadas (fallback a ffmpeg)
- `unrar` — archivos .rar
- `jq` — conteo rápido de playlists

---

## 🧠 Características

- **Procesamiento paralelo** — detecta CPU y RAM, ajusta trabajos automáticamente
- **Detección inteligente de loop** — pymusiclooper analiza los puntos de repetición
- **Portada automática** — fondo difuminado + imagen centrada
- **Filtrado de duplicados** — elimina archivos idénticos por hash MD5
- **Portada desde YouTube** — si no pasas imagen, extrae el primer frame
- **Modo tester** — procesa solo 1 archivo para probar configuración
- **Apagado programado** — apaga el PC después de terminar (00:01-07:00)
- **Multi-plataforma** — funciona en Linux y macOS
- **Sin dependencias raras** — solo ffmpeg, yt-dlp y pymusiclooper

---

## 📄 Licencia

MIT

---

**Hecho con ❤️ para creadores de contenido en YouTube**
