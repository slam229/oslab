#!/bin/bash
set -e

echo "=== 从源码构建 x86 交叉编译工具链 ==="

CROSS_DIR="$HOME/sysuos-2026-spring-i386/lab1/cross-tools"
PREFIX="$CROSS_DIR/install"

mkdir -p "$CROSS_DIR"
cd "$CROSS_DIR"

# 2. 编译 GCC cross-compiler for i686-elf
echo "--- Step 2: gcc cross-compiler ---"
if [ ! -f gcc-12.2.0.tar.xz ]; then
    echo "下载 gcc..."
    wget -q https://mirrors.tuna.tsinghua.edu.cn/gnu/gcc/gcc-12.2.0/gcc-12.2.0.tar.xz
fi
if [ ! -d gcc-12.2.0 ]; then
    /usr/bin/tar -xvf gcc-12.2.0.tar.xz
    cd gcc-12.2.0
    # 下载依赖
    ./contrib/download_prerequisites
    cd ..
fi

export PATH="$PREFIX/bin:$PATH"
mkdir -p build-gcc
cd build-gcc
if [ ! -f Makefile ]; then
    ../gcc-12.2.0/configure --target=i686-elf --prefix="$PREFIX" \
        --disable-nls --enable-languages=c --without-headers \
        --disable-libssp --disable-libquadmath --disable-libstdcxx
fi
make -j4 all-gcc
make -j4 all-target-libgcc 
make install-gcc
make install-target-libgcc

echo "--- gcc 交叉编译器安装完成 ---"
ls "$PREFIX/bin/i686-elf-"* 
"$PREFIX/bin/i686-elf-gcc" --version 