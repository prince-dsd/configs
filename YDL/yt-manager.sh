#!/usr/bin/env bash

# ============================================================
#                    YT-DLP MANAGER v3
# ============================================================
#
# Interactive yt-dlp frontend for KDE neon / Linux
#
# Requirements:
#   yt-dlp
#   ffmpeg
#   deno
#   Firefox
#
# ============================================================

set -uo pipefail

# ============================================================
# APP CONFIGURATION
# ============================================================

APP_NAME="YT-DLP MANAGER"
CONFIG_DIR="$HOME/.config/yt-dlp-manager"
CONFIG_FILE="$CONFIG_DIR/config"
ARCHIVE_FILE="$CONFIG_DIR/downloaded.txt"

DOWNLOAD_DIR="$HOME/Downloads/yt-dlp"
CONTAINER="mp4"
FIREFOX_PROFILE=""

mkdir -p "$CONFIG_DIR"
mkdir -p "$DOWNLOAD_DIR"

# ============================================================
# COLORS
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

# ============================================================
# GLOBAL VARIABLES
# ============================================================

URL=""
TITLE=""
CHANNEL=""
DURATION=""

FORMAT=""
FORMAT_DESCRIPTION=""

PLAYLIST_MODE="single"
PLAYLIST_ITEMS=""

SUBTITLE_MODE="none"
SUBTITLE_LANGS="en,en-US"

AUDIO_MODE="best"

# ============================================================
# LOAD CONFIG
# ============================================================

load_config() {

    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    fi

    mkdir -p "$DOWNLOAD_DIR"
}

# ============================================================
# SAVE CONFIG
# ============================================================

save_config() {

    cat > "$CONFIG_FILE" <<EOF
DOWNLOAD_DIR=$(printf '%q' "$DOWNLOAD_DIR")
CONTAINER=$(printf '%q' "$CONTAINER")
FIREFOX_PROFILE=$(printf '%q' "$FIREFOX_PROFILE")
EOF
}

# ============================================================
# BANNER
# ============================================================

banner() {

    clear

    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"
    printf "║  %-54s║\n" "$APP_NAME"
    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ============================================================
# PAUSE
# ============================================================

pause() {

    echo
    read -rp "Press Enter to continue..."
}

# ============================================================
# ERROR
# ============================================================

error_message() {

    echo
    echo -e "${RED}ERROR:${NC} $1"
    pause
}

# ============================================================
# DETECT FIREFOX PROFILE
# ============================================================

detect_firefox_profile() {

    # Existing configured profile
    if [[ -n "$FIREFOX_PROFILE" ]] &&
       [[ -f "$FIREFOX_PROFILE/cookies.sqlite" ]]; then
        return 0
    fi

    local search_paths=(
        "$HOME/.config/mozilla/firefox"
        "$HOME/.mozilla/firefox"
    )

    local candidates=()

    for base in "${search_paths[@]}"; do

        [[ -d "$base" ]] || continue

        while IFS= read -r file; do
            candidates+=("$(dirname "$file")")
        done < <(
            find "$base" \
                -maxdepth 3 \
                -type f \
                -name "cookies.sqlite" \
                2>/dev/null
        )
    done

    if [[ ${#candidates[@]} -eq 0 ]]; then
        FIREFOX_PROFILE=""
        return 1
    fi

    # Prefer default-release
    for profile in "${candidates[@]}"; do

        if [[ "$profile" == *".default-release"* ]]; then
            FIREFOX_PROFILE="$profile"
            save_config
            return 0
        fi

    done

    # Otherwise first available profile
    FIREFOX_PROFILE="${candidates[0]}"

    save_config

    return 0
}

# ============================================================
# DEPENDENCY CHECK
# ============================================================

check_dependencies() {

    local missing=()

    command -v yt-dlp >/dev/null 2>&1 ||
        missing+=("yt-dlp")

    command -v ffmpeg >/dev/null 2>&1 ||
        missing+=("ffmpeg")

    command -v deno >/dev/null 2>&1 ||
        missing+=("deno")

    if [[ ${#missing[@]} -gt 0 ]]; then

        banner

        echo -e "${RED}Missing dependencies:${NC}"
        echo

        for item in "${missing[@]}"; do
            echo "  • $item"
        done

        echo
        echo "Install them and run this program again."

        pause

        exit 1
    fi

    detect_firefox_profile

    if [[ -z "$FIREFOX_PROFILE" ]]; then

        echo
        echo -e "${YELLOW}Firefox profile was not detected.${NC}"
        echo
        echo "You can configure it later from Settings."
        echo
        pause

    fi
}

# ============================================================
# COMMON YT-DLP ARGUMENTS
# ============================================================

yt_base_args() {

    YT_ARGS=(
        "--remote-components"
        "ejs:github"
    )

    if [[ -n "$FIREFOX_PROFILE" ]]; then

        YT_ARGS+=(
            "--cookies-from-browser"
            "firefox:$FIREFOX_PROFILE"
        )

    fi
}

# ============================================================
# RUN YT-DLP
# ============================================================

run_ytdlp() {

    yt_base_args

    yt-dlp "${YT_ARGS[@]}" "$@"
}

# ============================================================
# URL INPUT
# ============================================================

get_url() {

    echo
    echo "Enter a YouTube URL."
    echo
    echo "Examples:"
    echo "  Video:    https://www.youtube.com/watch?v=..."
    echo "  Playlist: https://www.youtube.com/playlist?list=..."
    echo

    read -rp "URL: " URL

    if [[ -z "$URL" ]]; then
        return 1
    fi

    return 0
}

# ============================================================
# VIDEO INFORMATION
# ============================================================

fetch_video_info() {

    local info

    info=$(run_ytdlp \
        --no-playlist \
        --no-warnings \
        --print "%(title)s" \
        --print "%(channel)s" \
        --print "%(duration_string)s" \
        "$URL" 2>/dev/null)

    if [[ $? -ne 0 || -z "$info" ]]; then
        return 1
    fi

    TITLE=$(printf '%s\n' "$info" | sed -n '1p')
    CHANNEL=$(printf '%s\n' "$info" | sed -n '2p')
    DURATION=$(printf '%s\n' "$info" | sed -n '3p')

    return 0
}

# ============================================================
# GET FORMATS
# ============================================================

get_formats() {

    FORMAT_FILE=$(mktemp)

    if ! run_ytdlp \
        --no-playlist \
        --no-warnings \
        --list-formats \
        "$URL" > "$FORMAT_FILE" 2>&1; then

        cat "$FORMAT_FILE"
        rm -f "$FORMAT_FILE"

        return 1
    fi

    return 0
}

# ============================================================
# EXTRACT RESOLUTIONS
# ============================================================

get_resolutions() {

    local file="$1"

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
        ' "$file" |

        grep -E '^[0-9]+$' |

        sort -rn |

        uniq
    )
}

# ============================================================
# QUALITY MENU
# ============================================================

quality_menu() {

    if ! get_formats; then
        pause
        return 1
    fi

    get_resolutions "$FORMAT_FILE"

    if [[ ${#RESOLUTIONS[@]} -eq 0 ]]; then

        echo
        echo -e "${RED}No video resolutions detected.${NC}"

        cat "$FORMAT_FILE"

        rm -f "$FORMAT_FILE"

        pause

        return 1
    fi

    banner

    echo -e "${WHITE}VIDEO QUALITY${NC}"
    echo

    local i=1

    for height in "${RESOLUTIONS[@]}"; do

        local label=""

        case "$height" in
            4320) label="8K" ;;
            2160) label="4K UHD" ;;
            1440) label="2K QHD" ;;
            1080) label="Full HD" ;;
            720)  label="HD" ;;
            480)  label="SD" ;;
            360)  label="Low" ;;
            240)  label="Very Low" ;;
            144)  label="Very Low" ;;
        esac

        printf "  ${CYAN}%2d${NC}) ${WHITE}%4sp${NC}  %s\n" \
            "$i" "$height" "$label"

        ((i++))

    done

    echo
    echo "  ${CYAN}A${NC}) Best available"
    echo "  ${CYAN}C${NC}) Custom format"
    echo "  ${CYAN}B${NC}) Back"
    echo

    read -rp "Selection: " choice

    case "$choice" in

        [Aa])

            FORMAT="bv*+ba/b"
            FORMAT_DESCRIPTION="Best available"

            ;;

        [Cc])

            echo
            echo "Examples:"
            echo "  bv*+ba/b"
            echo "  bv*[height<=1080]+ba/b"
            echo

            read -rp "Format expression: " FORMAT

            [[ -n "$FORMAT" ]] ||
                return 1

            FORMAT_DESCRIPTION="Custom format"

            ;;

        [Bb])

            rm -f "$FORMAT_FILE"

            return 1

            ;;

        *)

            if [[ "$choice" =~ ^[0-9]+$ ]] &&
               (( choice >= 1 && choice <= ${#RESOLUTIONS[@]} )); then

                local height="${RESOLUTIONS[$((choice-1))]}"

                FORMAT="bv*[height<=${height}]+ba/b[height<=${height}]"

                FORMAT_DESCRIPTION="${height}p + best audio"

            else

                echo
                echo -e "${RED}Invalid selection.${NC}"

                rm -f "$FORMAT_FILE"

                pause

                return 1

            fi

            ;;

    esac

    rm -f "$FORMAT_FILE"

    return 0
}

# ============================================================
# CONTAINER MENU
# ============================================================

container_menu() {

    banner

    echo -e "${WHITE}VIDEO CONTAINER${NC}"
    echo

    echo "  1) MP4"
    echo "  2) MKV"
    echo "  3) WebM"
    echo "  B) Back"
    echo

    read -rp "Selection: " choice

    case "$choice" in

        1)
            CONTAINER="mp4"
            ;;

        2)
            CONTAINER="mkv"
            ;;

        3)
            CONTAINER="webm"
            ;;

        [Bb])
            return
            ;;

        *)
            echo "Invalid selection."
            pause
            return
            ;;
    esac

    save_config
}

# ============================================================
# PLAYLIST MENU
# ============================================================

playlist_menu() {

    banner

    echo -e "${WHITE}PLAYLIST MODE${NC}"
    echo

    echo "  1) Current video only"
    echo "  2) Entire playlist"
    echo "  3) Playlist range"
    echo "  4) Specific videos"
    echo "  B) Back"
    echo

    read -rp "Selection: " choice

    case "$choice" in

        1)

            PLAYLIST_MODE="single"
            PLAYLIST_ITEMS=""

            ;;

        2)

            PLAYLIST_MODE="all"
            PLAYLIST_ITEMS=""

            ;;

        3)

            read -rp "Enter range (example 1-10): " PLAYLIST_ITEMS

            [[ -n "$PLAYLIST_ITEMS" ]] ||
                return 1

            PLAYLIST_MODE="range"

            ;;

        4)

            read -rp "Enter videos (example 1,4,7): " PLAYLIST_ITEMS

            [[ -n "$PLAYLIST_ITEMS" ]] ||
                return 1

            PLAYLIST_MODE="items"

            ;;

        [Bb])

            return 1

            ;;

        *)

            echo "Invalid selection."
            pause

            return 1

            ;;

    esac

    return 0
}

# ============================================================
# SUBTITLE MENU
# ============================================================

subtitle_menu() {

    banner

    echo -e "${WHITE}SUBTITLES${NC}"
    echo

    echo "  1) No subtitles"
    echo "  2) Download subtitles"
    echo "  3) Download + embed subtitles"
    echo "  B) Back"
    echo

    read -rp "Selection: " choice

    case "$choice" in

        1)

            SUBTITLE_MODE="none"

            ;;

        2)

            SUBTITLE_MODE="download"

            ;;

        3)

            SUBTITLE_MODE="embed"

            ;;

        [Bb])

            return 1

            ;;

        *)

            echo "Invalid selection."
            pause

            return 1

            ;;
    esac

    if [[ "$SUBTITLE_MODE" != "none" ]]; then

        echo
        read -rp \
            "Languages (example en,en-US): " \
            SUBTITLE_LANGS

        [[ -n "$SUBTITLE_LANGS" ]] ||
            SUBTITLE_LANGS="en,en-US"

    fi

    return 0
}

# ============================================================
# AUDIO MENU
# ============================================================

audio_menu() {

    banner

    echo -e "${WHITE}AUDIO DOWNLOAD${NC}"
    echo

    echo "  1) Best audio"
    echo "  2) MP3"
    echo "  3) M4A"
    echo "  4) Opus"
    echo "  5) FLAC"
    echo "  B) Back"
    echo

    read -rp "Selection: " choice

    case "$choice" in

        1)
            AUDIO_MODE="best"
            ;;

        2)
            AUDIO_MODE="mp3"
            ;;

        3)
            AUDIO_MODE="m4a"
            ;;

        4)
            AUDIO_MODE="opus"
            ;;

        5)
            AUDIO_MODE="flac"
            ;;

        [Bb])
            return 1
            ;;

        *)
            echo "Invalid selection."
            pause
            return 1
            ;;
    esac

    return 0
}

# ============================================================
# DOWNLOAD VIDEO
# ============================================================

download_video() {

    if ! quality_menu; then
        return
    fi

    if ! playlist_menu; then
        return
    fi

    banner

    echo -e "${WHITE}DOWNLOAD OPTIONS${NC}"
    echo
    echo "Quality:    $FORMAT_DESCRIPTION"
    echo "Container:  $CONTAINER"
    echo

    case "$PLAYLIST_MODE" in

        single)
            echo "Mode:       Single video"
            OUTPUT="$DOWNLOAD_DIR/%(title)s.%(ext)s"
            ;;

        all)
            echo "Mode:       Entire playlist"
            OUTPUT="$DOWNLOAD_DIR/%(playlist_title)s/%(playlist_index)03d - %(title)s.%(ext)s"
            ;;

        range)
            echo "Mode:       Playlist range"
            echo "Items:      $PLAYLIST_ITEMS"
            OUTPUT="$DOWNLOAD_DIR/%(playlist_title)s/%(playlist_index)03d - %(title)s.%(ext)s"
            ;;

        items)
            echo "Mode:       Selected playlist items"
            echo "Items:      $PLAYLIST_ITEMS"
            OUTPUT="$DOWNLOAD_DIR/%(playlist_title)s/%(playlist_index)03d - %(title)s.%(ext)s"
            ;;

    esac

    echo "Destination: $DOWNLOAD_DIR"
    echo

    read -rp "Start download? [Y/n]: " confirm

    [[ "$confirm" =~ ^[Nn]$ ]] && return

    yt_base_args

    local args=(
        "${YT_ARGS[@]}"

        --continue
        --no-overwrites
        --ignore-errors

        --format "$FORMAT"

        --output "$OUTPUT"

        --download-archive "$ARCHIVE_FILE"
    )

    case "$PLAYLIST_MODE" in

        single)
            args+=(--no-playlist)
            ;;

        all)
            args+=(--yes-playlist)
            ;;

        range|items)
            args+=(
                --yes-playlist
                --playlist-items "$PLAYLIST_ITEMS"
            )
            ;;

    esac

    # Container
    case "$CONTAINER" in

        mp4)
            args+=(--merge-output-format mp4)
            ;;

        mkv)
            args+=(--merge-output-format mkv)
            ;;

        webm)
            args+=(--merge-output-format webm)
            ;;

    esac

    # Subtitles
    if [[ "$SUBTITLE_MODE" == "download" ||
          "$SUBTITLE_MODE" == "embed" ]]; then

        args+=(
            --write-subs
            --sub-langs "$SUBTITLE_LANGS"
        )

        if [[ "$SUBTITLE_MODE" == "embed" ]]; then
            args+=(--embed-subs)
        fi

    fi

    echo
    echo -e "${GREEN}Starting download...${NC}"
    echo

    yt-dlp "${args[@]}" "$URL"

    local status=$?

    echo

    if [[ $status -eq 0 ]]; then

        echo -e "${GREEN}Download completed successfully.${NC}"

    else

        echo -e "${YELLOW}Download completed with errors.${NC}"

    fi

    pause
}

# ============================================================
# DOWNLOAD AUDIO
# ============================================================

download_audio() {

    if ! audio_menu; then
        return
    fi

    banner

    echo -e "${WHITE}AUDIO DOWNLOAD${NC}"
    echo
    echo "Mode: $AUDIO_MODE"
    echo "Destination: $DOWNLOAD_DIR"
    echo

    read -rp "Start download? [Y/n]: " confirm

    [[ "$confirm" =~ ^[Nn]$ ]] && return

    yt_base_args

    local args=(
        "${YT_ARGS[@]}"

        --no-playlist

        --continue

        --no-overwrites

        --download-archive "$ARCHIVE_FILE"

        --format "ba/b"

        --output "$DOWNLOAD_DIR/%(title)s.%(ext)s"
    )

    if [[ "$AUDIO_MODE" != "best" ]]; then

        args+=(
            --extract-audio
            --audio-format "$AUDIO_MODE"
        )

    fi

    yt-dlp "${args[@]}" "$URL"

    pause
}

# ============================================================
# DOWNLOAD SUBTITLES
# ============================================================

download_subtitles() {

    if ! subtitle_menu; then
        return
    fi

    [[ "$SUBTITLE_MODE" == "none" ]] &&
        return

    yt_base_args

    local args=(
        "${YT_ARGS[@]}"

        --no-playlist

        --skip-download

        --write-subs

        --sub-langs "$SUBTITLE_LANGS"

        --output "$DOWNLOAD_DIR/%(title)s.%(ext)s"
    )

    if [[ "$SUBTITLE_MODE" == "embed" ]]; then
        args+=(--embed-subs)
    fi

    yt-dlp "${args[@]}" "$URL"

    pause
}

# ============================================================
# DOWNLOAD THUMBNAIL
# ============================================================

download_thumbnail() {

    banner

    echo -e "${WHITE}THUMBNAIL${NC}"
    echo
    echo "Download the highest-quality available thumbnail."
    echo

    read -rp "Continue? [Y/n]: " confirm

    [[ "$confirm" =~ ^[Nn]$ ]] && return

    run_ytdlp \
        --no-playlist \
        --skip-download \
        --write-thumbnail \
        --output "$DOWNLOAD_DIR/%(title)s.%(ext)s" \
        "$URL"

    pause
}

# ============================================================
# FORMAT INFORMATION
# ============================================================

show_formats() {

    banner

    echo -e "${WHITE}AVAILABLE FORMATS${NC}"
    echo

    run_ytdlp \
        --no-playlist \
        --list-formats \
        "$URL"

    pause
}

# ============================================================
# SETTINGS
# ============================================================

settings_menu() {

    while true; do

        banner

        echo -e "${WHITE}SETTINGS${NC}"
        echo

        echo "Download directory:"
        echo "  $DOWNLOAD_DIR"
        echo

        echo "Firefox profile:"
        echo "  ${FIREFOX_PROFILE:-Not configured}"
        echo

        echo "Container:"
        echo "  $CONTAINER"
        echo

        echo "  1) Change download directory"
        echo "  2) Change Firefox profile"
        echo "  3) Container"
        echo "  4) Automatically detect Firefox profile"
        echo "  5) Test Firefox cookies"
        echo "  B) Back"
        echo

        read -rp "Selection: " choice

        case "$choice" in

            1)

                echo
                read -rp "New directory: " newdir

                if [[ -n "$newdir" ]]; then

                    newdir="${newdir/#\~/$HOME}"

                    DOWNLOAD_DIR="$newdir"

                    mkdir -p "$DOWNLOAD_DIR"

                    save_config

                fi

                ;;

            2)

                echo
                read -rp "Firefox profile directory: " profile

                if [[ -f "$profile/cookies.sqlite" ]]; then

                    FIREFOX_PROFILE="$profile"

                    save_config

                    echo
                    echo -e "${GREEN}Firefox profile saved.${NC}"

                else

                    echo
                    echo -e "${RED}cookies.sqlite not found.${NC}"

                fi

                pause

                ;;

            3)

                container_menu

                ;;

            4)

                FIREFOX_PROFILE=""

                if detect_firefox_profile; then

                    echo
                    echo -e "${GREEN}Detected:${NC}"
                    echo "$FIREFOX_PROFILE"

                else

                    echo
                    echo -e "${RED}No Firefox profile found.${NC}"

                fi

                pause

                ;;

            5)

                banner

                if [[ -z "$FIREFOX_PROFILE" ]]; then

                    echo -e "${RED}Firefox profile is not configured.${NC}"

                else

                    echo "Profile:"
                    echo "$FIREFOX_PROFILE"
                    echo

                    yt_base_args

                    if yt-dlp \
                        "${YT_ARGS[@]}" \
                        --no-playlist \
                        --print "%(title)s" \
                        "https://www.youtube.com/watch?v=z2CB-smCvYY" \
                        >/dev/null 2>&1; then

                        echo -e "${GREEN}Firefox cookies are readable.${NC}"

                    else

                        echo -e "${YELLOW}Cookie test failed.${NC}"
                        echo "Make sure Firefox is closed and try again."

                    fi

                fi

                pause

                ;;

            [Bb])

                return

                ;;

            *)

                echo "Invalid selection."
                pause

                ;;

        esac

    done
}

# ============================================================
# OPEN DOWNLOAD DIRECTORY
# ============================================================

open_download_directory() {

    mkdir -p "$DOWNLOAD_DIR"

    if command -v dolphin >/dev/null 2>&1; then

        dolphin "$DOWNLOAD_DIR" >/dev/null 2>&1 &

    elif command -v xdg-open >/dev/null 2>&1; then

        xdg-open "$DOWNLOAD_DIR" >/dev/null 2>&1 &

    else

        echo "$DOWNLOAD_DIR"
        pause

    fi
}

# ============================================================
# VERSION INFORMATION
# ============================================================

show_versions() {

    banner

    echo -e "${WHITE}SYSTEM INFORMATION${NC}"
    echo

    echo "yt-dlp:"
    yt-dlp --version

    echo
    echo "ffmpeg:"
    ffmpeg -version | head -n 1

    echo
    echo "Deno:"
    deno --version | head -n 1

    echo
    echo "Firefox profile:"
    echo "${FIREFOX_PROFILE:-Not detected}"

    pause
}

# ============================================================
# URL SESSION
# ============================================================

url_session() {

    while true; do

        if ! get_url; then
            return
        fi

        echo
        echo -e "${YELLOW}Fetching information...${NC}"

        if ! fetch_video_info; then

            echo
            echo -e "${RED}Unable to access this URL.${NC}"
            pause

            continue
        fi

        while true; do

            banner

            echo -e "${GREEN}CURRENT VIDEO${NC}"
            echo

            echo "Title:"
            echo "  $TITLE"
            echo

            echo "Channel:"
            echo "  $CHANNEL"
            echo

            echo "Duration:"
            echo "  $DURATION"
            echo

            echo "  1) Download video"
            echo "  2) Download audio"
            echo "  3) Download subtitles"
            echo "  4) Download thumbnail"
            echo "  5) Show formats"
            echo "  6) Enter another URL"
            echo "  B) Back"
            echo

            read -rp "Selection: " choice

            case "$choice" in

                1)
                    download_video
                    ;;

                2)
                    download_audio
                    ;;

                3)
                    download_subtitles
                    ;;

                4)
                    download_thumbnail
                    ;;

                5)
                    show_formats
                    ;;

                6)
                    break
                    ;;

                [Bb])
                    return
                    ;;

                *)
                    echo "Invalid selection."
                    pause
                    ;;

            esac

        done

    done
}

# ============================================================
# MAIN MENU
# ============================================================

main_menu() {

    while true; do

        banner

        echo -e "${WHITE}MAIN MENU${NC}"
        echo

        echo "  1) Enter YouTube URL"
        echo "  2) Settings"
        echo "  3) Show versions"
        echo "  4) Open download directory"
        echo "  Q) Quit"
        echo

        echo -e "${GRAY}Download directory:${NC}"
        echo "  $DOWNLOAD_DIR"
        echo

        read -rp "Selection: " choice

        case "$choice" in

            1)
                url_session
                ;;

            2)
                settings_menu
                ;;

            3)
                show_versions
                ;;

            4)
                open_download_directory
                ;;

            [Qq])
                clear
                echo "Goodbye."
                exit 0
                ;;

            *)
                echo "Invalid selection."
                pause
                ;;

        esac

    done
}

# ============================================================
# START
# ============================================================

load_config

check_dependencies

main_menu
