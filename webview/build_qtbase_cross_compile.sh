#!/bin/bash

# vim: tabstop=4 shiftwidth=4 softtabstop=4
# -*- sh-basic-offset: 4 -*-

set -exuo pipefail

BUILD_TARGET=/build
SRC=/src
QT_BRANCH="5.15.2"
DEBIAN_VERSION=$(lsb_release -cs)

mkdir -p "$BUILD_TARGET"
mkdir -p "$SRC"

/usr/games/cowsay -f tux "Building QT Base version $QT_BRANCH."

function fetch_rpi_tools () {
    if [ ! -d "/src/tools" ]; then
        cd /src
        git clone https://github.com/raspberrypi/tools
    fi
}

function fetch_rpi_firmware () {
    if [ ! -d "/src/opt" ]; then
        cd /src

        # We do an `svn checkout` here as the entire git repo here is *huge*
        # and `git` doesn't  support partial checkouts well (yet)
        svn checkout https://github.com/raspberrypi/firmware/trunk/opt
    fi
    rsync -aP /src/opt/ /sysroot/opt/
}

function fetch_qt () {
    local SRC_DIR="/src/qtbase"
    if [ ! -d "$SRC_DIR" ]; then
        git clone git://code.qt.io/qt/qtbase.git -b "$QT_BRANCH" "$SRC_DIR"

        # Patch QT
        #git clone https://github.com/oniongarlic/qt-raspberrypi-configuration.git
        #cd qt-raspberrypi-configuration
        #make install DESTDIR=../
    else
        cd "$SRC_DIR"
        git reset --hard
        git clean -dfx
    fi
}

function fetch_qtwebengine () {
    local SRC_DIR="/src/qtwebengine"
    if [ ! -d "$SRC_DIR" ]; then
        git clone git://code.qt.io/qt/qtwebengine.git -b "$QT_BRANCH" "$SRC_DIR"
        cd "$SRC_DIR"
        git submodule init
        git submodule update

    else
        cd "$SRC_DIR"
        git reset --hard
        git clean -dfx
    fi

    # Patch up WebEngine due to GCC bug
    # https://www.enricozini.org/blog/2020/qt5/build-qt5-cross-builder-with-raspbian-sysroot-compiling-with-the-sysroot/
    #cd "$SRC_DIR"
    #sed -i '1s/^/#pragma GCC push_options\n#pragma GCC optimize ("O0")\n/' src/3rdparty/chromium/third_party/skia/third_party/skcms/skcms.cc
    #echo "#pragma GCC pop_options" >> src/3rdparty/chromium/third_party/skia/third_party/skcms/skcms.cc
}

function build_qtbase () {
    # This build process is inspired by
    # https://www.tal.org/tutorials/building-qt-512-raspberry-pi
    local SRC_DIR="/src/$1"

    if [ ! -f "$BUILD_TARGET/qtbase-$QT_BRANCH-$DEBIAN_VERSION-$1.tar.gz" ]; then
        /usr/games/cowsay -f tux "Building QT Base for $1"
        mkdir -p "$SRC_DIR"
        cd "$SRC_DIR"

        # Patch up QT
        #sed -i 's/lEGL/lbrcmEGL/' "/src/qtbase/mkspecs/devices/linux-rasp-$1-g++/qmake.conf"
        #sed -i 's/lGLESv2/lbrcmGLESv2/' "/src/qtbase/mkspecs/devices/linux-rasp-$1-g++/qmake.conf"

        /src/qtbase/configure \
            -confirm-license \
            -device "linux-rasp-$1-g++" \
            -device-option CROSS_COMPILE=/src/tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin/arm-linux-gnueabihf- \
            -eglfs \
            -evdev \
            -extprefix "$SRC_DIR/qt5pi" \
            -force-pkg-config \
            -glib \
            -no-compile-examples \
            -no-cups \
            -no-gbm \
            -no-gtk \
            -no-pch \
            -no-use-gold-linker \
            -nomake examples \
            -opengl es2 \
            -opensource \
            -prefix /usr/local/qt5pi \
            -qpa eglfs \
            -qt-freetype \
            -qt-pcre \
            -reduce-exports \
            -release \
            -skip qtlocation \
            -skip qtscript \
            -skip qtwayland \
            -ssl \
            -system-libjpeg \
            -system-libpng \
            -system-zlib \
            -sysroot /sysroot

        # Break here for now
        read

        make -j "$(nproc --all)"
        make install
        cp -r /usr/share/fonts/truetype/dejavu/ "$SRC_DIR/qt5pi/lib/fonts"

        /usr/games/cowsay -f tux "Building QTWebEngine for $1"
        fetch_qtwebengine
        cd /src/qtwebengine
        "$SRC_DIR/qt5pi/bin/qmake"

        # Break here for now
        read

        NINJAJOBS=-j1 make -j "$(nproc --all)"
        make install

        cd "$SRC_DIR"
        tar -zcvf "$BUILD_TARGET/qtbase-$QT_BRANCH-$DEBIAN_VERSION-$1.tar.gz" qt5pi
        cd "$BUILD_TARGET"
        sha256sum "qtbase-$QT_BRANCH-$DEBIAN_VERSION-$1.tar.gz" > "qtbase-$QT_BRANCH-$DEBIAN_VERSION-$1.tar.gz.sha256"
    else
        echo "Build already exist."
    fi
}


function build_qtbase_pi4 () {
    # We can probably refactor the other `build_qtbase` function to include these
    # unique build options, but this will do for now even if it isn't DRY.
    local SRC_DIR="/src/pi4"
    if [ ! -f "$BUILD_TARGET/qtbase-$QT_BRANCH-$DEBIAN_VERSION-pi4.tar.gz" ]; then
        /usr/games/cowsay -f tux "Building QT Base for Pi 4"
        mkdir -p "$SRC_DIR"
        cd "$SRC_DIR"
        /src/qtbase/configure \
            -platform linux-rpi4-v3d-g++ \
            -opengl es2 \
            -eglfs \
            -no-gtk \
            -opensource \
            -confirm-license \
            -release \
            -reduce-exports \
            -force-pkg-config \
            -nomake examples \
            -no-compile-examples \
            -skip qtwayland \
            -qt-pcre \
            -no-pch \
            -ssl \
            -evdev \
            -system-freetype \
            -fontconfig \
            -glib \
            -prefix /usr/local/qt5pi \
            -no-cups \
            -extprefix "$SRC_DIR/qt5pi" \
            -qpa eglfs

        make -j "$(nproc --all)"
        make install
        cp -r /usr/share/fonts/truetype/dejavu/ "$SRC_DIR/qt5pi/lib/fonts"

        /usr/games/cowsay -f tux "Building QTWebEngine for Pi 4"
        fetch_qtwebengine
        cd /src/qtwebengine
        "$SRC_DIR/qt5pi/bin/qmake"
        NINJAJOBS=-j1 make -j "$(nproc --all)"
        make install

        cd "$SRC_DIR"
        tar -zcvf "$BUILD_TARGET/qtbase-$QT_BRANCH-$DEBIAN_VERSION-pi4.tar.gz" qt5pi
        cd "$BUILD_TARGET"
        sha256sum "qtbase-$QT_BRANCH-$DEBIAN_VERSION-pi4.tar.gz" > "qtbase-$QT_BRANCH-$DEBIAN_VERSION-pi4.tar.gz.sha256"
    fi
}

/usr/local/bin/sysroot-relativelinks.py /sysroot

fetch_qt
fetch_rpi_tools
fetch_rpi_firmware
build_qtbase pi
build_qtbase pi2
build_qtbase pi3
build_qtbase_pi4