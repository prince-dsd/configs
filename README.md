# Configurations Repository

A collection of utility scripts for managing Docker, Kodi media center, and YouTube content downloading on Linux systems.

## Directory Structure

### Root Level Scripts

- **`clean_docker.sh`** - Removes all Docker containers, images, and stops running services
- **`kodi_joystick.sh`** - Maps gamepad/joystick input to Kodi media center commands via JSON-RPC API
- **`gamepad_json.sh`** - Alternative joystick-to-Kodi controller for sending input commands
- **`gamepad_kodi.c`** - C source code for direct joystick device input handling
- **`prekodi.sh`** - Pre-launch initialization script for Kodi with Bluetooth and IPTV setup

### YDL Directory

YouTube content downloading tools powered by yt-dlp:

- **`yt-manager.sh`** - Interactive yt-dlp frontend with configuration management
- **`yt-dlp-v3.sh`** - Enhanced yt-dlp manager version 3 for KDE Neon / Linux
- **`yt-dl.sh`** - Basic interactive YouTube downloader with Firefox integration
- **`yt-manager-colorful-v4.sh`** - Feature-rich version 4 with colored output
- **`yt-manager-codec-selection.sh`** - Advanced codec and format selection options

## Features by Category

### 🎮 Kodi & Gamepad Integration
- Configure and connect gamepad controllers to Kodi
- Send remote control commands via joystick input
- Automatic device discovery and mapping
- Supports multiple Kodi instances via network JSON-RPC

### 📥 YouTube Download Tools
- Interactive CLI for downloading YouTube content
- Format and quality selection
- Archive tracking to prevent re-downloads
- FFmpeg integration for post-processing
- Browser profile integration for authentication

### 🐳 Docker Management
- Quick cleanup of all Docker containers and images
- Useful for fresh starts and resource cleanup

### 🎵 Kodi Startup
- Automated Bluetooth device connection
- Audio sink configuration
- IPTV server health checking
- KDE application launcher integration

## Prerequisites

### General
- Linux OS (KDE Neon recommended for full compatibility)
- Bash shell

### For Kodi Scripts
- Kodi media center instance
- JSON-RPC API access enabled
- Curl for HTTP requests
- Joystick/gamepad device
- Netcat (nc) for port checking

### For YouTube Download Scripts
- `yt-dlp` (https://github.com/yt-dlp/yt-dlp)
- `ffmpeg`
- `deno` (for manager versions)
- Firefox (optional, for browser integration)

### For Docker Script
- Docker installed and configured

## Usage

### Basic Kodi Joystick Setup
```bash
# Configure joystick name and Kodi credentials
nano kodi_joystick.sh
# Edit JOYSTICK_NAME, KODI_HOST, KODI_USER, KODI_PASS

# Run the script
chmod +x kodi_joystick.sh
./kodi_joystick.sh
```

### YouTube Download
```bash
# Run interactive downloader
chmod +x YDL/yt-manager.sh
./YDL/yt-manager.sh

# Or use the basic version
./YDL/yt-dl.sh
```

### Kodi Startup Sequence
```bash
chmod +x prekodi.sh
./prekodi.sh
# Connects Bluetooth device, configures audio, checks IPTV server, launches Kodi
```

### Docker Cleanup
```bash
chmod +x clean_docker.sh
./clean_docker.sh
```

## Configuration

Most scripts include configuration sections at the top with customizable variables:

- **Kodi Connection**: Host, port, username, password
- **Download Paths**: Output directory for YouTube content
- **Device Settings**: Joystick names, audio sink preferences
- **Bluetooth Addresses**: Device MAC addresses for auto-connect

## Requirements Summary

| Component | Tools |
|-----------|-------|
| Kodi Remote Control | curl, netcat |
| YouTube Download | yt-dlp, ffmpeg |
| Audio Management | PulseAudio (pactl) or WirePlumber (wpctl) |
| System Interaction | deno (optional, for enhanced managers) |
| Bluetooth | bluetoothctl |

## License

MIT License - see [LICENSE](LICENSE) file for details

## Notes

- Ensure all scripts have execute permissions: `chmod +x *.sh`
- Update configuration variables (credentials, paths, device names) before first use
- Some scripts are designed for specific Linux distributions (KDE Neon) but may work on other distros
- Kodi JSON-RPC API must be enabled in Kodi settings
