#!/bin/bash
# ============================================================================
# 麒麟操作系统 arm64, x86_64 → i386 交叉编译
#
# 宿主: 麒麟 Linux Advanced Server V11 (aarch64)
# 目标: i386 32位
# ============================================================================

LAB1_DIR="$HOME/sysuos-2026-spring-i386/lab1"
CROSS_INSTALL="$LAB1_DIR/cross-tools/install"
MUSL_INSTALL="$CROSS_INSTALL/i686-linux-musl"
RESULTS_DIR="$LAB1_DIR/results_i386"
KERNEL_DIR="$LAB1_DIR/linux-5.10.19"
LINUX011_DIR="$LAB1_DIR/linux-0.11"

export PATH="$CROSS_INSTALL/bin:$PATH"
mkdir -p "$RESULTS_DIR"

GREEN='\033[0;32m'; RED='\033[0;31m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_section() { echo -e "\n${BLUE}================================================================${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}================================================================${NC}\n"; }
log_ok()   { echo -e "${GREEN}[OK] $1${NC}"; }
log_fail() { echo -e "${RED}[FAIL] $1${NC}"; }
log_info() { echo -e "${YELLOW}[INFO] $1${NC}"; }

# ============================================================================
# Step 0: 构建 musl-libc for i686 (helloworld 和 busybox 的前置依赖)
# ============================================================================
build_musl() {
    log_section "Step 0: 构建 musl-libc for i686"

    if [ -f "$MUSL_INSTALL/lib/libc.a" ]; then
        log_ok "musl-libc 已存在，跳过构建"
        return 0
    fi

    cd "$LAB1_DIR/cross-tools"
    MUSL_VER="musl-1.2.4"

    if [ ! -f "${MUSL_VER}.tar.gz" ]; then
        log_info "下载 musl-libc..."
        wget -q --show-progress "https://musl.libc.org/releases/${MUSL_VER}.tar.gz" || {
            log_fail "musl 下载失败"; return 1
        }
    fi

    if [ ! -d "$MUSL_VER" ]; then
        tar xf "${MUSL_VER}.tar.gz"
    fi

    cd "$MUSL_VER"
    make clean 2>/dev/null || true

    log_info "配置 musl (CC=i686-linux-gnu-gcc, target=i686)..."
    CC=i686-linux-gnu-gcc ./configure \
        --prefix="$MUSL_INSTALL" \
        --host=i686-linux-gnu \
        --disable-shared

    log_info "编译 musl..."
    make -j$(nproc) 
    make install

    # 用 musl 自带脚本生成 specs 文件
    MUSL_SRC="$LAB1_DIR/cross-tools/$MUSL_VER"
    if [ -f "$MUSL_SRC/tools/musl-gcc.specs.sh" ]; then
        sh "$MUSL_SRC/tools/musl-gcc.specs.sh" \
            "$MUSL_INSTALL/include" "$MUSL_INSTALL/lib" "/lib/ld-musl-i386.so.1" \
            > "$MUSL_INSTALL/lib/musl-gcc.specs"
        log_ok "musl-gcc.specs 已生成"
    fi

    # 安装 i386 Linux 内核头文件到 musl sysroot（busybox 需要）
    if [ -d "$KERNEL_DIR" ]; then
        log_info "安装 i386 内核头文件到 musl sysroot..."
        cd "$KERNEL_DIR"
        make ARCH=i386 headers_install INSTALL_HDR_PATH="$MUSL_INSTALL"
    fi

    # 创建 musl-gcc 包装脚本
cat > "$CROSS_INSTALL/bin/i686-linux-musl-gcc" << 'EOF'
#!/bin/sh
REALPATH=$(dirname "$(readlink -f "$0")")
MUSL_ROOT=$(dirname "$REALPATH")/i686-linux-musl

exec "$REALPATH/i686-linux-gnu-gcc" "$@" -specs "$MUSL_ROOT/lib/musl-gcc.specs"
EOF
chmod +x "$CROSS_INSTALL/bin/i686-linux-musl-gcc"

    # 修正后的符号链接（确保在目标目录执行）
    (
        cd "$CROSS_INSTALL/bin" || exit
        for tool in ar as ld nm objcopy objdump ranlib readelf strip; do
            ln -sf "i686-linux-gnu-$tool" "i686-linux-musl-$tool"
        done
    )

    if [ -f "$MUSL_INSTALL/lib/libc.a" ] && [ -f "$MUSL_INSTALL/lib/musl-gcc.specs" ]; then
        log_ok "musl-libc 构建成功"
        ls -lh "$MUSL_INSTALL/lib/libc.a"
    else
        log_fail "musl-libc 构建失败"
        return 1
    fi
}

# ============================================================================
# 主函数
# ============================================================================
main() {
    echo "============================================================================"
    echo "  Lab1 i386 库文件生成 - 麒麟操作系统 (ARM64 → i386 交叉编译)"
    echo "  时间: $(date)"
    echo "  系统: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
    echo "  架构: $(uname -m) (宿主) → i386 (目标)"
    echo "============================================================================"

    build_musl  
    echo ""

    log_section "编译完成"
    echo "完成时间: $(date)"
}

main