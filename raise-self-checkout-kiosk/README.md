# RAISE Self-Checkout Kiosk

A lightweight, standalone smart self-checkout kiosk terminal engineered to run smoothly on low-cost hardware (e.g. Raspberry Pi 3B+/4/5, or any browser with a webcam).

Shoppers identify with a secure QR pass or NFC card, scan items via a standard USB camera (using dual WebAssembly decoders plus a blur-tolerant pattern matcher), and pay via UPI QR code.

---

## 1. Highlights & Architecture

* **Zero Framework Overhead:** Pure Vanilla HTML5, CSS3, and modern JavaScript for instant boot times and 60fps rendering even on low-spec hardware.
* **Dual WASM Decoders:** Leverages both ZXing and ZBar WebAssembly binaries in background Web Workers (`scan-worker.js`) to maximize barcode scan hit rates across noisy environments.
* **Blur-Tolerant EAN Matcher (`barcode-match.js`):** When decoders fail due to bad focus or low-resolution webcams, compares scanned line patterns directly against known catalog EAN items.
* **Hardware Bridges:**
  * **NFC Bridge (`kiosk/nfc-bridge.py`):** Reads PN532 (I2C) or RC522 (SPI) RFID cards and types `nfc-<uid>` into Linux `uinput` like a virtual keyboard, bypassing browser hardware access constraints.
  * **Buzzer Bridge (`kiosk/buzzer-bridge.py`):** A localhost HTTP daemon (`127.0.0.1:8799/beep`) allowing web pages to trigger physical GPIO buzzer audio feedback for scans, logins, errors, and payment.
* **Offline-Ready:** Built-in catalog caching, local passes, and a service worker (`sw.js`) ensure self-checkout continues operating even during network outages.

---

## 2. Directory Structure

```
raise-self-checkout-kiosk/
├── index.html              - Kiosk application (attract, identify, scan, checkout, paid)
├── scanner.js              - Camera capture and worker scheduling
├── scan-worker.js          - Web Worker running WASM decoders in parallel
├── barcode-match.js        - Pattern matching fallback for blurry barcodes
├── catalog.js              - Product catalog & Open Food Facts fallback
├── cloud.js                - Backend Edge Function API client
├── cloud-config.js         - Public Supabase project URL & anon key
├── cloud-config.example.js - Template for connecting to a live cloud project
├── pass.js                 - Pass formatting & legacy offline pass decoding
├── shared.js               - UI toasts, themes, buzzer triggers, and SVG icons
├── style.css, raise.css    - Kiosk responsive UI layout & design tokens
├── sw.js, manifest.json    - PWA offline caching & installation configuration
├── vendor/                 - ZXing & ZBar WebAssembly binaries, QR generator
├── img/                    - Product thumbnails and iconography
├── tests/                  - Automated test suite (node:test)
│   └── kiosk.test.mjs      - Unit tests for barcode, NFC, and buzzer contracts
└── kiosk/                  - Raspberry Pi provisioning & Python hardware bridges
    ├── buzzer-bridge.py    - Localhost HTTP bridge to GPIO buzzer
    ├── nfc-bridge.py       - NFC to virtual keyboard bridge
    ├── setup-kiosk.sh      - Full-screen Chromium autostart script
    ├── setup-buzzer.sh     - GPIO buzzer service setup
    ├── setup-nfc.sh        - NFC reader service setup
    ├── setup-all.sh        - One-command Pi installer
    └── PI_DEPLOYMENT_GUIDE.md - Complete Pi hardware setup instructions
```

---

## 3. Quick Start (Local Laptop / Dev)

### Prerequisites
* Node.js 20+ or Python 3.8+
* Modern Chromium-based browser (Chrome, Edge, Brave) with webcam access

### Run the Kiosk
```bash
# Option A: With Python
python -m http.server 8080

# Option B: With Node.js
npm test     # Run automated test suite
npm run serve # Launch on http://localhost:8080
```

Open `http://localhost:8080` in your browser. (The browser will ask for webcam permission on first load).

---

## 4. Raspberry Pi Deployment

On a fresh Raspberry Pi OS (Bookworm or Bullseye):

```bash
# 1. Clone or copy this directory to the Pi (/home/pi/raise-kiosk)
cd /home/pi/raise-kiosk

# 2. Run the one-command installer
bash kiosk/setup-all.sh http://localhost:8080/
```

This script automatically configures:
* Auto-login to desktop.
* Screen blanking & screensaver disabled.
* Chromium kiosk mode with pre-approved webcam access.
* Systemd background services for `raise-buzzer` and `raise-nfc`.
* Automatic restart on reboot.

---

## 5. Automated Tests

```bash
npm test
```
Validates:
* 12-digit UPC-A to 13-digit EAN-13 padding.
* Virtual NFC keyboard input extraction and SHA-256 hash generation.
* Localhost buzzer-bridge HTTP query parameter formatting.
* `RAISE2` HMAC token structure verification.

