#!/bin/bash
set -e

echo "=== 从源码构建 x86 交叉编译工具链 ==="

CROSS_DIR="$HOME/sysuos-2026-spring-i386/lab1/cross-tools"
PREFIX="$CROSS_DIR/install"

mkdir -p "$CROSS_DIR"
cd "$CROSS_DIR"

# 1. 编译 binutils for i686-elf
echo "--- Step 1: binutils ---"
if [ ! -f binutils-2.36.tar.xz ]; then
    echo "下载 binutils..."
    wget -q https://mirrors.tuna.tsinghua.edu.cn/gnu/binutils/binutils-2.36.tar.xz
fi
if [ ! -d binutils-2.36 ]; then
    /usr/bin/tar -xvf binutils-2.36.tar.xz
fi

mkdir -p build-binutils
cd build-binutils

echo "Configuring..."
../binutils-2.36/configure --target=i686-elf --prefix="$PREFIX" --disable-nls --disable-werror
if [ $? -ne 0 ]; then
    echo "Error: Configure failed!"
    exit 1
fi

echo "Building..."
make -j$(nproc)
if [ $? -ne 0 ]; then
    echo "Error: Build failed!"
    exit 1
fi

echo "Installing..."
make install

echo "--- binutils 安装完成 ---"
ls "$PREFIX/bin/i686-elf-"* 
cd "$CROSS_DIR"