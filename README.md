# Aevis Desktop Shell

Core desktop shell process for the Aevis Desktop Environment: status bar, dock, launcher, and desktop overview managed in a single high-performance process sharing a unified QML engine.

Part of the **[Project Aevis](https://github.com/project-Aevis)** suite.

## Architecture

Each desktop component maintains its own window and D-Bus service identity while running in a shared runtime process.

Desktop icon rendering and wallpaper management are provided by the file manager's `org.cutefish.filemanager.desktop` / `org.aevis.filemanager.desktop` module.

## Dependencies

### Debian / Ubuntu

```shell
sudo apt install cmake extra-cmake-modules pkg-config build-essential \
    qt6-base-dev qt6-declarative-dev qt6-tools-dev kwayland-dev
```

Requires **[FishUI](https://github.com/project-Aevis/fishui)** and **[File Manager](https://github.com/project-Aevis/filemanager)** installed before building.

## Build and Install

```shell
mkdir build
cd build
cmake -DCMAKE_INSTALL_PREFIX=/usr ..
make
sudo make install
```

## Running under Wayland

To start manually under an existing Wayland compositor (e.g. KWin Wayland):

```shell
QT_QPA_PLATFORM=wayland ./build/aevis-shell
```

## License

This project is licensed under the GNU General Public License v3.0 (GPLv3).
