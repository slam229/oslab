#!/bin/bash
set -e

# ============================================================================
# 配置区域
# ============================================================================
LAB1_DIR="$HOME/sysuos-2026-spring-i386/lab1"
CROSS_DIR="$LAB1_DIR/cross-tools"
PREFIX="$CROSS_DIR/install"
TARGET="i686-linux-gnu"
KERNEL_VER="5.10.19"
KERNEL_DIR="$LAB1_DIR/linux-$KERNEL_VER"

mkdir -p "$CROSS_DIR"
cd "$CROSS_DIR"
export PATH="$PREFIX/bin:$PATH"

# ============================================================================
# Step 0: 下载并准备 Linux 内核头文件 (针对 i386)
# ============================================================================
log_info() { echo -e "\033[1;33m[INFO] $1\033[0m"; }

if [ ! -d "$KERNEL_DIR" ]; then
    if [ ! -f "linux-$KERNEL_VER.tar.xz" ]; then
        log_info "未找到内核源码，正在从清华源下载..."
        wget -c https://mirrors.tuna.tsinghua.edu.cn/kernel/v5.x/linux-$KERNEL_VER.tar.xz
    fi
    log_info "正在解压内核源码...请耐心等待"
    tar -xf linux-$KERNEL_VER.tar.xz -C "$LAB1_DIR"
    log_info "正在导出 i386 架构内核头文件到 sysroot..."
    cd "$KERNEL_DIR"
    # 必须强行指定 ARCH=i386
    make ARCH=i386 INSTALL_HDR_PATH="$PREFIX/$TARGET" headers_install
    cd "$CROSS_DIR"
fi

# ============================================================================
# Step 1: 编译 GCC (Bootstrap 阶段)
# ============================================================================
log_info "--- Step 1: 编译 $TARGET-gcc ---"

if [ ! -d "gcc-12.2.0" ]; then
    if [ ! -f "gcc-12.2.0.tar.xz" ]; then
        log_info "正在下载 GCC 12.2.0..."
        wget -c https://mirrors.tuna.tsinghua.edu.cn/gnu/gcc/gcc-12.2.0/gcc-12.2.0.tar.xz
    fi
    tar -xf gcc-12.2.0.tar.xz
    cd gcc-12.2.0
    log_info "下载 GCC 依赖库 (mpfr, gmp, mpc)..."
    ./contrib/download_prerequisites
    cd ..
fi

mkdir -p build-gcc
cd build-gcc

if [ ! -f Makefile ]; then
    log_info "正在配置 GCC..."
    ../gcc-12.2.0/configure \
        --target="$TARGET" \
        --prefix="$PREFIX" \
        --with-sysroot="$PREFIX/$TARGET" \
        --enable-languages=c \
        --with-newlib \
        --without-headers \
        --disable-shared \
        --disable-threads \
        --disable-libssp \
        --disable-libquadmath \
        --disable-libgomp \
        --disable-libatomic \
        --disable-nls \
        --with-arch=i686 \
        --with-gnu-as \
        --with-gnu-ld
fi

log_info "开始并行编译 GCC (可能会持续 20-60 分钟)..."
make -j$(nproc) all-gcc
make -j$(nproc) all-target-libgcc 

log_info "正在安装编译器..."
make install-gcc
make install-target-libgcc

echo "===================================================================="
echo " 成功！你的交叉编译器已就绪: $PREFIX/bin/$TARGET-gcc"
echo " 现在你可以使用它来编译 musl-libc 并最终生成 32 位静态程序了。"
echo "===================================================================="