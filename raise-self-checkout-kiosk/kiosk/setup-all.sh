#!/usr/bin/env bash
# RAISE All-in-One Provisioning Script for Raspberry Pi
# Sets up Chromium Kiosk, Local Server, GPIO Buzzer, and NFC Reader in one command.
#
# Usage:
#   bash setup-all.sh                                  # Local mode + active buzzer + auto NFC
#   bash setup-all.sh --url https://your-domain.com    # Hosted mode
#   bash setup-all.sh --nfc rc522 --buzzer passive     # Custom hardware options
#   bash setup-all.sh --no-nfc                         # Kiosk + Buzzer only
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
URL=""
NFC_TYPE="auto"
BUZZER_TYPE="active"
BUZZER_PIN="18"
SKIP_NFC=0
SKIP_BUZZER=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --url) URL="$2"; shift 2 ;;
        --nfc) NFC_TYPE="$2"; shift 2 ;;
        --no-nfc) SKIP_NFC=1; shift ;;
        --buzzer) BUZZER_TYPE="$2"; shift 2 ;;
        --no-buzzer) SKIP_BUZZER=1; shift ;;
        --pin) BUZZER_PIN="$2"; shift 2 ;;
        -h|--help)
            echo "RAISE All-in-One Raspberry Pi Setup"
            echo "Options:"
            echo "  --url <URL>            Hosted kiosk URL (omit for local mode on localhost:8080)"
            echo "  --nfc <auto|pn532|rc522> NFC reader type (default: auto)"
            echo "  --no-nfc               Skip NFC reader setup"
            echo "  --buzzer <active|passive> Buzzer type (default: active)"
            echo "  --no-buzzer            Skip buzzer setup"
            echo "  --pin <BCM_GPIO>       Buzzer GPIO pin (default: 18)"
            exit 0
            ;;
        *)
            if [ -z "$URL" ] && [[ "$1" =~ ^https?:// ]]; then
                URL="$1"; shift
            else
                echo "Unknown option: $1" >&2; exit 1
            fi
            ;;
    esac
done

if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: Please run this script as your regular user (e.g. 'pi'), NOT with sudo." >&2
    echo "The installer will prompt for sudo credentials when required." >&2
    exit 1
fi

echo "=========================================================="
echo "         RAISE Raspberry Pi All-in-One Setup              "
echo "=========================================================="
echo " Mode:        $([ -n "$URL" ] && echo "Hosted ($URL)" || echo "Local (http://localhost:8080)")"
echo " Buzzer:      $([ "$SKIP_BUZZER" -eq 1 ] && echo "Disabled" || echo "$BUZZER_TYPE on GPIO $BUZZER_PIN")"
echo " NFC Reader:  $([ "$SKIP_NFC" -eq 1 ] && echo "Disabled" || echo "$NFC_TYPE")"
echo "=========================================================="
sleep 1

# 1. Kiosk & Chromium Setup
echo ""
echo ">>> [1/3] Setting up Chromium Kiosk & Display..."
if [ -n "$URL" ]; then
    bash "$HERE/setup-kiosk.sh" "$URL"
else
    bash "$HERE/setup-kiosk.sh"
fi

# 2. Buzzer Setup
if [ "$SKIP_BUZZER" -eq 0 ]; then
    echo ""
    echo ">>> [2/3] Setting up GPIO Buzzer Bridge..."
    BUZZER_PIN="$BUZZER_PIN" bash "$HERE/setup-buzzer.sh" "$BUZZER_TYPE"
else
    echo ""
    echo ">>> [2/3] Skipping Buzzer setup (--no-buzzer)."
fi

# 3. NFC Setup
if [ "$SKIP_NFC" -eq 0 ]; then
    echo ""
    echo ">>> [3/3] Setting up NFC Reader Bridge..."
    bash "$HERE/setup-nfc.sh" "$NFC_TYPE"
else
    echo ""
    echo ">>> [3/3] Skipping NFC setup (--no-nfc)."
fi

echo ""
echo "=========================================================="
echo "            RAISE Pi Provisioning Complete!               "
echo "=========================================================="
echo "Services status:"
echo " - Kiosk Server: $(systemctl is-active raise-kiosk-server 2>/dev/null || echo 'not active / hosted mode')"
if [ "$SKIP_BUZZER" -eq 0 ]; then
    echo " - Buzzer Bridge: $(systemctl is-active raise-buzzer 2>/dev/null || echo 'installed')"
fi
if [ "$SKIP_NFC" -eq 0 ]; then
    echo " - NFC Bridge:    $(systemctl is-active raise-nfc 2>/dev/null || echo 'installed')"
fi
echo ""
echo "Next Steps:"
echo " 1. Connect your hardware (USB Webcam, NFC module, GPIO Buzzer)."
echo " 2. Reboot your Raspberry Pi now to apply display and interface changes:"
echo "      sudo reboot"
echo "=========================================================="

