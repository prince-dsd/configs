#!/usr/bin/env bash

# ============================================================
# Interactive yt-dlp YouTube Downloader
# KDE neon / Linux
# ============================================================

set -uo pipefail

# -----------------------------
# Configuration
# -----------------------------

YTDLP="yt-dlp"
DOWNLOAD_DIR="$HOME/Downloads/yt-dlp"
FIREFOX_PROFILE="$HOME/.config/mozilla/firefox/xfneiwth.default-release"

# -----------------------------
# Colors
# -----------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
NC='\033[0m'

# -----------------------------
# Functions
# -----------------------------

die() {
    echo -e "${RED}ERROR:${NC} $1"
    exit 1
}

pause() {
    read -rp "Press Enter to continue..."
}

# -----------------------------
# Dependency checks
# -----------------------------

command -v "$YTDLP" >/dev/null 2>&1 ||
    die "yt-dlp is not installed."

command -v ffmpeg >/dev/null 2>&1 ||
    die "ffmpeg is not installed."

command -v deno >/dev/null 2>&1 ||
    die "Deno is not installed."

[[ -d "$FIREFOX_PROFILE" ]] ||
    die "Firefox profile not found:
$FIREFOX_PROFILE"

mkdir -p "$DOWNLOAD_DIR"

# -----------------------------
# Header
# -----------------------------

clear

echo -e "${CYAN}"
echo "============================================================"
echo "                 yt-dlp Interactive Downloader"
echo "============================================================"
echo -e "${NC}"

echo "Download directory:"
echo "  $DOWNLOAD_DIR"
echo

# -----------------------------
# Ask for URL
# -----------------------------

read -rp "Enter YouTube video/playlist URL: " URL

[[ -n "$URL" ]] || die "No URL entered."

echo
echo -e "${YELLOW}Fetching available formats...${NC}"
echo

# -----------------------------
# Get format information
# -----------------------------

FORMAT_FILE=$(mktemp)

trap 'rm -f "$FORMAT_FILE"' EXIT

"$YTDLP" \
    --remote-components ejs:github \
    --cookies-from-browser "firefox:$FIREFOX_PROFILE" \
    --no-warnings \
    --flat-playlist \
    --print "%(id)s" \
    "$URL" >/dev/null 2>&1

if [[ $? -ne 0 ]]; then
    echo
    echo -e "${YELLOW}Could not access the URL.${NC}"
    echo "Make sure the video is accessible in your Firefox account."
    exit 1
fi

# For format detection we only inspect the first video.
"$YTDLP" \
    --remote-components ejs:github \
    --cookies-from-browser "firefox:$FIREFOX_PROFILE" \
    --no-playlist \
    --no-warnings \
    --list-formats \
    "$URL" > "$FORMAT_FILE" 2>&1

if grep -q "^ERROR:" "$FORMAT_FILE"; then
    cat "$FORMAT_FILE"
    exit 1
fi

# -----------------------------
# Extract available resolutions
# -----------------------------

mapfile -t RESOLUTIONS < <(
    awk '
    /^[[:space:]]*[0-9]+/ {
        for (i=1; i<=NF; i++) {
            if ($i ~ /^[0-9]+x[0-9]+$/) {
                split($i,a,"x")
                print a[2]
            }
        }
    }
    ' "$FORMAT_FILE" |
    grep -E '^[0-9]+$' |
    sort -rn |
    uniq
)

# -----------------------------
# Check formats
# -----------------------------

if [[ ${#RESOLUTIONS[@]} -eq 0 ]]; then
    echo
    cat "$FORMAT_FILE"
    echo
    die "No video formats were found."
fi

# -----------------------------
# Quality menu
# -----------------------------

echo
echo -e "${CYAN}============================================================${NC}"
echo -e "${WHITE}                 Available Video Qualities${NC}"
echo -e "${CYAN}============================================================${NC}"
echo

INDEX=1

for HEIGHT in "${RESOLUTIONS[@]}"; do

    case "$HEIGHT" in
        2160) LABEL="4K UHD" ;;
        1440) LABEL="2K QHD" ;;
        1080) LABEL="Full HD" ;;
        720)  LABEL="HD" ;;
        480)  LABEL="SD" ;;
        360)  LABEL="Low" ;;
        240)  LABEL="Low" ;;
        144)  LABEL="Very Low" ;;
        *)    LABEL="" ;;
    esac

    if [[ -n "$LABEL" ]]; then
        printf "  %2d) %-5sp  %s\n" "$INDEX" "$HEIGHT" "$LABEL"
    else
        printf "  %2d) %-5sp\n" "$INDEX" "$HEIGHT"
    fi

    ((INDEX++))
done

echo
echo "  A) Best available quality"
echo "  M) Audio only"
echo "  C) Custom yt-dlp format"
echo "  Q) Quit"
echo

read -rp "Select quality: " CHOICE

# -----------------------------
# Process selection
# -----------------------------

if [[ "$CHOICE" =~ ^[Qq]$ ]]; then
    echo "Cancelled."
    exit 0
fi

if [[ "$CHOICE" =~ ^[Aa]$ ]]; then

    FORMAT="bv*+ba/b"
    FORMAT_DESCRIPTION="Best available"

elif [[ "$CHOICE" =~ ^[Mm]$ ]]; then

    FORMAT="ba/b"
    FORMAT_DESCRIPTION="Audio only"

elif [[ "$CHOICE" =~ ^[Cc]$ ]]; then

    echo
    read -rp "Enter yt-dlp format expression: " FORMAT

    [[ -n "$FORMAT" ]] || die "No format specified."

    FORMAT_DESCRIPTION="Custom: $FORMAT"

elif [[ "$CHOICE" =~ ^[0-9]+$ ]] &&
     (( CHOICE >= 1 && CHOICE <= ${#RESOLUTIONS[@]} )); then

    HEIGHT="${RESOLUTIONS[$((CHOICE-1))]}"

    # Best video at or below the requested height,
    # combined with best available audio.
    FORMAT="bv*[height<=${HEIGHT}]+ba/b[height<=${HEIGHT}]"

    FORMAT_DESCRIPTION="${HEIGHT}p + best audio"

else
    die "Invalid selection."
fi

# -----------------------------
# Playlist menu
# -----------------------------

echo
echo -e "${CYAN}Playlist options${NC}"
echo
echo "  1) Current video only"
echo "  2) Entire playlist"
echo "  3) Cancel"
echo

read -rp "Select [1-3]: " PLAYLIST_CHOICE

case "$PLAYLIST_CHOICE" in

    1)
        PLAYLIST_OPTION="--no-playlist"
        OUTPUT="$DOWNLOAD_DIR/%(title)s.%(ext)s"
        ;;

    2)
        PLAYLIST_OPTION="--yes-playlist"
        OUTPUT="$DOWNLOAD_DIR/%(playlist_title)s/%(playlist_index)03d - %(title)s.%(ext)s"
        ;;

    3)
        echo "Cancelled."
        exit 0
        ;;

    *)
        die "Invalid playlist choice."
        ;;

esac

# -----------------------------
# Audio/video output
# -----------------------------

if [[ "$CHOICE" =~ ^[Mm]$ ]]; then
    MERGE_OPTION=""
else
    MERGE_OPTION="--merge-output-format mp4"
fi

# -----------------------------
# Confirmation
# -----------------------------

echo
echo -e "${CYAN}============================================================${NC}"
echo -e "${WHITE}                       Download${NC}"
echo -e "${CYAN}============================================================${NC}"
echo
echo "URL:       $URL"
echo "Format:    $FORMAT_DESCRIPTION"

if [[ "$PLAYLIST_CHOICE" == "2" ]]; then
    echo "Mode:      Entire playlist"
else
    echo "Mode:      Single video"
fi

echo "Location:  $DOWNLOAD_DIR"
echo

read -rp "Start download? [Y/n]: " CONFIRM

if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# -----------------------------
# Download
# -----------------------------

echo
echo -e "${GREEN}Starting download...${NC}"
echo

"$YTDLP" \
    --remote-components ejs:github \
    --cookies-from-browser "firefox:$FIREFOX_PROFILE" \
    "$PLAYLIST_OPTION" \
    --continue \
    --no-overwrites \
    --format "$FORMAT" \
    $MERGE_OPTION \
    --output "$OUTPUT" \
    --progress \
    "$URL"

STATUS=$?

echo

# -----------------------------
# Result
# -----------------------------

if [[ $STATUS -eq 0 ]]; then

    echo -e "${GREEN}"
    echo "============================================================"
    echo "                 Download completed!"
    echo "============================================================"
    echo -e "${NC}"

else

    echo -e "${RED}"
    echo "============================================================"
    echo "                 Download failed!"
    echo "============================================================"
    echo -e "${NC}"

    exit $STATUS
fi
