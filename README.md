# AndroidFileSync

A free, native macOS app to transfer files between your Mac and Android phone — over USB or WiFi.

No cloud. No Google account needed. Plug in via USB or connect wirelessly over WiFi.

![SwiftUI](https://img.shields.io/badge/SwiftUI-macOS%2013%2B-blue)

## Features

### Connectivity
- **USB Connection** — Plug in and go, zero config
- **Wireless ADB (Android 11+)** — Connect over WiFi without a cable
- **Zero-Latency Auto-Discovery** — Instantly find pairable network devices
- **Advanced Pairing Mode** — Explicitly enter IP, port, and pairing code for complex setups or VPNs

- **Smart Wi-Fi Multi-Device Selector** — Effortlessly juggle multiple Android phones attached to the same network directly from a dropdown

- **Context-Aware WiFi Connect** — Easily "Disconnect" devices natively if they're currently tied up on the network
### File Management
- **File Browser** — Browse your phone's storage like a native Finder window
- **Drag & Drop** — Drag files from Finder straight to your phone
- **Parallel Transfers** — Upload/download multiple files simultaneously
- **Conflict Resolution** — Intelligently detects existing duplicates during uploads, offering clean options to Skip or Replace All. 
- **Collision Prevention** — Renaming or pasting files safely generates unique names or warns you before overwriting data.
- **Smart Quick Access Sidebar** — Jump to Camera, Downloads, Pictures, Music, etc. Automatically sweeps away folders that don't exist on your specific device.
- **Native macOS Dialogs** — Polished, robust text-input panels for file renaming and folder creation that feel right at home on Mac.
- **Search & Sort** — Search files instantly, sort by name, size, date, or type
- **Batch Operations** — Change extensions, delete multiple files at once
- **Copy & Paste / Cut** — Clipboard operations across folders on the device
- **Trash Management** — Move to trash & restore, just like macOS
- **File Preview** — Double-click to preview images, videos, PDFs, and documents
- **Resizable Transfer Panel** — Collapsible progress view with drag-to-resize

## Prerequisites

- macOS 13.0 (Ventura) or later
- Android device (USB cable or WiFi for wireless)
- USB Debugging enabled on your Android device (see below)
- For wireless: **Wireless Debugging** enabled (Android 11+)

## Setup

### USB Connection

#### Step 1: Enable Developer Options

1. Open **Settings** on your Android phone
2. Scroll down and tap **About Phone**
3. Find **Build Number** and tap it **7 times**
4. You'll see a toast: *"You are now a developer!"*

> On some phones (Samsung), go to **Settings → About Phone → Software Information → Build Number**

#### Step 2: Enable USB Debugging

1. Go back to **Settings**
2. Tap **Developer Options** (now visible near the bottom)
3. Toggle **USB Debugging** to **ON**
4. Tap **OK** on the confirmation dialog

#### Step 3: Connect & Authorize

1. Connect your phone to your Mac via USB cable
2. On your phone, you'll see a prompt: **"Allow USB debugging?"**
3. Check **"Always allow from this computer"**
4. Tap **Allow**

> **Tip:** If you don't see the prompt, try disconnecting and reconnecting the cable, or switch to a different USB port.

#### Step 4: Set USB Mode to File Transfer

1. After connecting, pull down the notification shade on your phone
2. Tap the **USB notification** (e.g., "Charging this device via USB")
3. Select **File Transfer / MTP**

#### Auto-Discovery Pairing (Easiest)

1. On your phone: **Developer Options → Wireless Debugging → ON**
2. Tap **Pair device with pairing code**
3. In the app: The **Auto-Discovery** tab will securely detect your IP and automatically pre-fill your `Pairing Port`.
4. Enter the **6-digit code** shown on your phone and click **Pair & Connect**.

> **Multiple Devices?** If multiple phones are broadcasting on the network, a seamless dropdown Selector will appear allowing you to select your target IP visually.

#### Advanced Pairing

1. On your phone: **Developer Options → Wireless Debugging → ON**
2. Tap **Pair device with pairing code** — note the IP, port, and code
3. In the app: Click **WiFi** button → **Advanced** tab → Manually enter the network details

## Installation

### From DMG (Recommended)

1. Download the latest `.dmg` from [Releases](#)
2. Open the DMG and drag **AndroidFileSync** to your Applications folder
3. **Important — remove Gatekeeper quarantine** (the app is not signed with an Apple Developer account):

   ```bash
   xattr -cr /Applications/AndroidFileSync.app
   ```

4. Launch the app — ADB is bundled, no additional setup needed

> **Why?** macOS blocks unsigned apps by default. The `xattr -cr` command removes the quarantine flag so the app can open normally. This is safe — the app is open source, you can verify the code yourself.

### Build from Source

```bash
git clone https://github.com/YourUsername/AndroidFileSync.git
cd AndroidFileSync
open AndroidFileSync.xcodeproj
```

Build and run with Xcode (⌘R).

To create a DMG:

```bash
./build-dmg.sh
```

## Usage

1. Connect your Android phone via **USB** or **WiFi** (click the WiFi button)
2. Launch AndroidFileSync
3. The app auto-detects your device and shows a connection badge (blue for USB, green for WiFi)
4. Browse, drag & drop, download, upload, preview — it just works
5. **Double-click** any file to preview it (images, videos, PDFs, documents)
6. **Right-click** for context menu (Preview, Download, Rename, Delete, Copy, Cut)

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Scanning for Device..." won't stop | Check USB Debugging is enabled and you tapped "Allow" on the phone |
| Device not detected | Try a different USB cable (some only charge, don't transfer data) |
| WiFi pairing fails | Ensure both devices are on the same WiFi network |
| WiFi pairing code not working | Re-open Wireless Debugging on your phone to get a fresh code and try again |
| Slow transfers | Use a USB 3.0 cable and port for faster speeds |
| Empty Trash not working | Reconnect the device and try again |
| App crashes on launch | Ensure macOS 13.0+ and try re-downloading |

## Tech Stack

- **SwiftUI** — Native macOS UI
- **ADB** — Android Debug Bridge (bundled with the app)
- **Swift Concurrency** — Async/await for parallel transfers
- **Network.framework** — mDNS service discovery for wireless pairing
- **CoreImage** — Image processing and thumbnail generation
- **Quick Look** — Native file preview via macOS default apps


