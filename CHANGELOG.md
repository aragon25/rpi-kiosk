# Changelog

All notable changes to this project will be documented in this file.

## [1.47-1] - TESTING

### Added
- Raspbian Trixie support

### Fixed
- usage text in help.
- kill kiosk processes softer
- configuring admin user by kiosk-init even if no app is declared
- prevent starting graphical target if installing from tty 

## [1.46-2] - 2025-11-24

### Changed
- first release for github

## [1.46-1] - 2025-07-29

### Added
- on-screen-keyboard: onboard with kiosk layout
- filemanager: xfe
- terminal: lxterminal
- panel for admin: tint2
- menu entries for admin: logout; setup kiosk-browser
- headless-mode if no display is connected (e.g. for VNC-connection)

### Fixed
- Bugfixes

### Changed
- moved kiosk home from /tmp to /usr/lib/rpi-kiosk.
- moved some files from /tmp to /run/user/2001.
- kiosk-browser: renamed defaultpage and added errorpage.
- kiosk-browser: switch to errorpage and back if website is not available.
- reload kiosk automatically after config changes
- initramfs-splash screen (now needs initramfs-splash >= 2.2-1)

## [1.45-3] - 2025-07-09

### Fixed
- Bugfixes

### Added
- default wallpaper.
- initramfs-splash screen (need initramfs-splash >= 2.1-2)

## [1.45-2] - 2025-07-08

### Fixed
- Bugfixes

## [1.45-1] - 2025-07-01

### Fixed
- Bugfixes

### Removed
- all bootfs relations.

### Changed
- Moved and renamed statefile from /boot to /STATIC or /etc folder.

## [1.44-1] - 2024-11-18

### Added
- First stable release
