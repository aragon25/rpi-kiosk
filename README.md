# rpi-kiosk

Raspberry Pi kiosk service and installer. 
Provides scripts and web UI assets to run a browser-based kiosk session or other
default application based session on Raspbian systems.
It includes installer helpers, a long-running service mode and per-user
startup helpers.

## 📌 Features

- Enable/disable kiosk service and user services (installer helper).
- Long-running service that monitors kiosk state and restarts sessions as
  needed.
- Per-session init helper that launches the browser UI, manages on-screen
  keyboard and wallpaper.
- Bundled offline web UI: `src/kiosk-browser/index.html`, `loader.html`,
  `error.html`.
- Config-driven via `/etc/rpi-kiosk/kiosk.conf` and `CONFIG_FILE.d/` drop-ins.

---

## 🧰 Dependencies

Runtime packages expected by the scripts:

- `lightdm`, `lightdm-gtk-greeter`, `lightdm-autologin-greeter`
- `openbox`, `xorg`, `xserver-xorg-video-dummy`, `x11-xserver-utils`
- `curl`, `wmctrl`, `feh`, `numlockx`

The scripts check for required packages at runtime and print instructions if
something is missing.

---

## 📁 Installation

### Option 1 — Install via `.deb` (recommended)

Build or download the release package and install on the device:

```bash
wget https://github.com/aragon25/rpi-kiosk/releases/download/v1.47-1/rpi-kiosk_1.47-1_all.deb
sudo apt install ./rpi-kiosk_1.47-1_all.deb
```

The package places scripts and supporting files into system locations; check
`deploy/config/build_deb.conf` for declared dependencies and packaging hooks.

---

## ⚙️ Usage

Run the main script as `root`. Only one option may be used at a time.

```bash
sudo rpi-kiosk --help
```

Options (selected):

- `-m, --adminmode`         start kiosk and enter admin mode
- `-a, --activate`          start kiosk and quit admin mode (if active)
- `-d, --deactivate`        stop kiosk and quit admin mode (if active)
- `-s, --settings`          print and test current active settings
- `-v, --version`           print version
- `-h, --help`              show help

---

## 📂 Files of interest

- `src/rpi-kiosk.sh` — main service and installer helper.
- `src/kiosk-init.sh` — per-session init and browser launcher.
- `src/kiosk-browser/` — bundled web UI and helper scripts.

---

## ⚠️ Safety & recommendations

- The scripts require `root` privileges for many operations (creating users,
  writing `/etc/` files, stopping display managers). Test on a disposable image
  or VM before using on production devices.
- Review packaging hooks in `deploy/config/*.sh` before installing generated
  packages.
- Back up network and auth-related files (e.g. `/etc/wpa_supplicant/`,
  `/etc/lightdm/`) before switching managers or installing.

## Examples

```bash
# activate kiosk
sudo rpi-kiosk --activate

# deactivate kiosk
sudo rpi-kiosk --deactivate

# Enter admin mode
sudo rpi-kiosk --adminmode
```