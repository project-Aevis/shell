cmake_minimum_required(VERSION 3.21)

project(cutefish-shell LANGUAGES C CXX)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(GNUInstallDirs)

find_package(Qt6 CONFIG REQUIRED Widgets DBus Concurrent Quick QuickControls2 Network LinguistTools)
find_package(KWayland REQUIRED)
find_package(KF6GlobalAccel REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(WAYLAND_CLIENT REQUIRED IMPORTED_TARGET wayland-client)

add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../cutefish-framework/applications
                 ${CMAKE_CURRENT_BINARY_DIR}/cutefish-framework-applications-build)

# What every module compiles against: one include root, so a cross-module
# include reads as the path it is ("core/window/shellsurface.h"), and the Qt
# and Wayland libraries the shell is built on.
add_library(shellcommon INTERFACE)
target_include_directories(shellcommon INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(shellcommon INTERFACE
    Cutefish::Applications
    Qt6::Core
    Qt6::Widgets
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Concurrent
    Qt6::DBus
    Qt6::Network
    KF6::GlobalAccel
    Plasma::KWaylandClient
    PkgConfig::WAYLAND_CLIENT
)

# One object library per module. Each owns its sources, its QML, its D-Bus glue
# and the QML types it publishes; the shell below only composes them.
# Infrastructure first: every component builds on the core windows and services.
add_subdirectory(src/core)
add_subdirectory(src/desktop)
add_subdirectory(src/statusbar)
add_subdirectory(src/dock)
add_subdirectory(src/launcher)
add_subdirectory(src/notification)

# QApplication rather than QGuiApplication: the status bar's application menu
# and several context menus are QWidget menus.
add_executable(cutefish-shell
    src/main.cpp
    src/shell.cpp
)

target_link_libraries(cutefish-shell PRIVATE
    shellcommon
    shell_core
    shell_desktop
    shell_statusbar
    shell_dock
    shell_launcher
    shell_notification
)

# ---------------------------------------------------------------------------
# Translations
#
# The merged components each brought their own catalogue with the same
# per-locale file names, so the sources are prefixed (dock_zh_CN.ts, ...) and
# the shell loads one catalogue per component at startup.
# ---------------------------------------------------------------------------
file(GLOB TS_FILES translations/*.ts)
qt6_add_translation(QM_FILES ${TS_FILES})
add_custom_target(translations DEPENDS ${QM_FILES} SOURCES ${TS_FILES})
add_dependencies(cutefish-shell translations)
install(FILES ${QM_FILES} DESTINATION /usr/share/cutefish-shell/translations)
install(FILES ${QM_FILES} DESTINATION /usr/share/aevis-shell/translations)

install(TARGETS cutefish-shell RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES data/cutefish-dock-list.conf DESTINATION /etc)
install(FILES data/aevis-dock-list.conf DESTINATION /etc)

install(CODE "execute_process(COMMAND \${CMAKE_COMMAND} -E create_symlink cutefish-shell \$ENV{DESTDIR}\${CMAKE_INSTALL_FULL_BINDIR}/aevis-shell)")

# KWin only hands org_kde_plasma_window_management (the protocol the dock and
# the status bar read the window list from) to clients whose desktop entry
# lists it in X-KDE-Wayland-Interfaces. It matches the entry to the client by
# comparing Exec against the process' executable path, and it does not resolve
# a bare command name against PATH, so Exec has to be absolute.
configure_file(data/cutefish-shell.desktop.in
               ${CMAKE_CURRENT_BINARY_DIR}/cutefish-shell.desktop @ONLY)
configure_file(data/aevis-shell.desktop.in
               ${CMAKE_CURRENT_BINARY_DIR}/aevis-shell.desktop @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/cutefish-shell.desktop
        DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/applications)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/aevis-shell.desktop
        DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/applications)

