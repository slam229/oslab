#!/bin/bash
# ============================================================================
# Lab1 i386 完整验证脚本 - 麒麟操作系统 ARM64 → i386 交叉编译
#
# 宿主: 麒麟 Linux Advanced Server V11 (aarch64)
# 目标: i386 32位
# 用法: bash verify_lab1_i386.sh [musl|1|2|3|4|5|6|7|8|all]
# ============================================================================

LAB1_DIR="$HOME/OSLab-i386-2026/lab1"
CROSS_INSTALL="$LAB1_DIR/cross-tools/install"
MUSL_INSTALL="$CROSS_INSTALL/i686-linux-musl"
RESULTS_DIR="$LAB1_DIR/results_i386"
KERNEL_DIR="$LAB1_DIR/linux-5.10.19"
BUSYBOX_DIR="$LAB1_DIR/busybox-1.36.1"
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
        --disable-shared 2>&1 | tail -5

    log_info "编译 musl..."
    make -j$(nproc) 2>&1 | tail -3
    make install 2>&1 | tail -3

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
        make ARCH=i386 headers_install INSTALL_HDR_PATH="$MUSL_INSTALL" 2>&1 | tail -3
    fi

    # 创建 musl-gcc 包装脚本
    cat > "$CROSS_INSTALL/bin/i686-linux-musl-gcc" << WEOF
#!/bin/sh
exec i686-linux-gnu-gcc "\$@" -specs "$MUSL_INSTALL/lib/musl-gcc.specs"
WEOF
    chmod +x "$CROSS_INSTALL/bin/i686-linux-musl-gcc"

    # 创建其他工具的符号链接
    for tool in ar as ld nm objcopy objdump ranlib readelf strip; do
        ln -sf "i686-linux-gnu-$tool" "$CROSS_INSTALL/bin/i686-linux-musl-$tool" 2>/dev/null
    done

    if [ -f "$MUSL_INSTALL/lib/libc.a" ] && [ -f "$MUSL_INSTALL/lib/musl-gcc.specs" ]; then
        log_ok "musl-libc 构建成功"
        ls -lh "$MUSL_INSTALL/lib/libc.a"
    else
        log_fail "musl-libc 构建失败"
        return 1
    fi
}

# ============================================================================
# Part 1: 环境配置验证
# ============================================================================
verify_part1() {
    log_section "第一部分：环境配置验证"

    echo "--- 操作系统信息 ---"
    cat /etc/os-release
    echo ""
    echo "--- CPU架构与内核 ---"
    uname -a
    echo ""
    echo "--- 本机 GCC ---"
    gcc --version | head -1
    echo ""
    echo "--- i386 交叉编译工具链 ---"
    echo "i686-linux-gnu-gcc: $(i686-linux-gnu-gcc --version 2>/dev/null | head -1)"
    echo "i686-elf-gcc:       $(i686-elf-gcc --version 2>/dev/null | head -1)"
    echo "i386-elf-gcc:       $(i386-elf-gcc --version 2>/dev/null | head -1)"
    if [ -x "$CROSS_INSTALL/bin/i686-linux-musl-gcc" ]; then
        echo "i686-linux-musl-gcc: 可用 (musl C库)"
    else
        echo "i686-linux-musl-gcc: 未构建 (运行: $0 musl)"
    fi
    echo ""
    echo "--- QEMU ---"
    for q in qemu-system-x86_64 qemu-system-i386 qemu-system-aarch64; do
        if which $q &>/dev/null; then log_ok "$q"; else echo "  $q: 未安装"; fi
    done
    echo ""
    echo "--- 开发工具 ---"
    for tool in nasm cmake bison flex bc make gdb strace wget; do
        if which $tool &>/dev/null; then log_ok "$tool"; else log_fail "$tool 未安装"; fi
    done
    echo ""
    log_ok "第一部分验证完成"
}

# ============================================================================
# Part 2: 编译 Linux 5.10.19 i386 内核 (已完成，仅验证)
# ============================================================================
verify_part2() {
    log_section "第二部分：编译 Linux 5.10.19 内核 (i386)"

    BZIMAGE="$KERNEL_DIR/arch/x86/boot/bzImage"
    VMLINUX="$KERNEL_DIR/vmlinux"

    if [ -f "$BZIMAGE" ]; then
        log_ok "bzImage 已存在"
        ls -lh "$BZIMAGE"
        file "$BZIMAGE"
        echo ""
        log_ok "vmlinux 符号表"
        ls -lh "$VMLINUX"
        file "$VMLINUX" | head -1
        echo ""
        echo "--- 编译配置 ---"
        echo "命令: make ARCH=i386 CROSS_COMPILE=i686-linux-gnu- i386_defconfig"
        echo "      ./scripts/config --enable CONFIG_DEBUG_INFO"
        echo "      make ARCH=i386 CROSS_COMPILE=i686-linux-gnu- -j\$(nproc)"
        grep -E 'CONFIG_X86_32=|CONFIG_DEBUG_INFO=|CONFIG_SMP=' "$KERNEL_DIR/.config"
    else
        log_fail "bzImage 不存在，需要先编译内核"
        echo "命令: cd $KERNEL_DIR"
        echo "      make ARCH=i386 CROSS_COMPILE=i686-linux-gnu- i386_defconfig"
        echo "      ./scripts/config --enable CONFIG_DEBUG_INFO"
        echo "      make ARCH=i386 CROSS_COMPILE=i686-linux-gnu- olddefconfig"
        echo "      make ARCH=i386 CROSS_COMPILE=i686-linux-gnu- -j\$(nproc)"
        return 1
    fi

    echo ""
    echo "--- 手动测试命令 (编译 i386 内核) ---"
    echo "============================================================"
    echo "cd $KERNEL_DIR"
    echo "make ARCH=i386 CROSS_COMPILE=i686-linux-gnu- i386_defconfig"
    echo "./scripts/config --enable CONFIG_DEBUG_INFO"
    echo "make ARCH=i386 CROSS_COMPILE=i686-linux-gnu- olddefconfig"
    echo "make ARCH=i386 CROSS_COMPILE=i686-linux-gnu- -j\$(nproc)"
    echo ""
    echo "# 验证编译结果"
    echo "file arch/x86/boot/bzImage   # Linux kernel x86 boot executable bzImage"
    echo "file vmlinux                  # ELF 32-bit LSB executable, Intel 80386, with debug_info"
    echo "============================================================"

    log_ok "第二部分验证完成"
}

# ============================================================================
# Part 3: 启动 i386 内核并调试
# ============================================================================
verify_part3() {
    log_section "第三部分：启动 i386 内核并调试 (QEMU + GDB)"

    BZIMAGE="$KERNEL_DIR/arch/x86/boot/bzImage"
    VMLINUX="$KERNEL_DIR/vmlinux"

    if [ ! -f "$BZIMAGE" ]; then
        log_fail "bzImage 不存在"; return 1
    fi

    echo "--- 3.1 启动 i386 内核 (无initramfs, 预期 Kernel panic) ---"
    echo "命令: qemu-system-x86_64 -kernel .../bzImage -append 'console=ttyS0' -nographic"
    echo "(ARM64上无qemu-system-i386, 使用qemu-system-x86_64兼容运行i386内核)"
    echo ""

    timeout 30 qemu-system-x86_64 -kernel "$BZIMAGE" \
        -append "console=ttyS0" -nographic 2>&1 || true

    echo ""
    echo "--- 3.2 GDB 远程调试 i386 内核 ---"
    echo "(ARM64 系统 gdb 不支持 i386，使用交叉编译的 x86_64-elf-gdb)"
    echo ""

    # 使用 x86_64-elf-gdb（匹配 qemu-system-x86_64 的 gdb stub）
    GDB_CMD="$CROSS_INSTALL/bin/x86_64-elf-gdb"
    if [ ! -x "$GDB_CMD" ]; then
        log_fail "x86_64-elf-gdb 不可用，需要先编译"
        log_info "编译方法: cd cross-tools && mkdir build-gdb-x86_64 && cd build-gdb-x86_64"
        log_info "../gdb-14.1/configure --prefix=.../install --target=x86_64-elf --program-prefix=x86_64-elf- --with-expat && make && make install"
        return 1
    fi

    # 启动 QEMU 后台 (-s -S 等待GDB)
    qemu-system-x86_64 -kernel "$BZIMAGE" -s -S \
        -append "console=ttyS0" -nographic &>/dev/null &
    QEMU_PID=$!
    sleep 3

    echo "--- 3.2.1 GDB 连接、单步执行、寄存器查看 ---"
    timeout 30 $GDB_CMD -batch \
        -ex "target remote :1234" \
        -ex "symbol-file $VMLINUX" \
        -ex "info registers rax rbx rcx rdx rsp rbp rip eflags cs ds" \
        -ex "stepi" \
        -ex "stepi" \
        -ex "stepi" \
        -ex "info registers rip eflags cs" \
        -ex "break start_kernel" \
        -ex "quit" 2>&1 || true

    kill $QEMU_PID 2>/dev/null; wait $QEMU_PID 2>/dev/null || true

    echo ""
    echo "--- 3.2.2 手动测试命令 (continue + 断点调试 start_kernel) ---"
    echo "============================================================"
    echo "注意: continue 到断点需要在交互式 GDB 中操作 (batch模式不支持异步等待)"
    echo ""
    echo "# 终端1: 启动 QEMU，冻结 CPU 等待 GDB 连接"
    echo "qemu-system-x86_64 -kernel $BZIMAGE -s -S -append 'console=ttyS0' -nographic"
    echo ""
    echo "# 终端2: 交互式 GDB 调试"
    echo "export PATH=$CROSS_INSTALL/bin:\$PATH"
    echo "x86_64-elf-gdb"
    echo "(gdb) target remote :1234                # 连接 QEMU gdb stub"
    echo "(gdb) symbol-file $VMLINUX               # 加载内核符号表"
    echo "(gdb) break start_kernel                  # 在 start_kernel 设置断点"
    echo "(gdb) continue                            # 运行，等待命中断点"
    echo "  ... 命中断点后 GDB 会自动停下并显示源码位置 ..."
    echo "(gdb) list                                # 查看 start_kernel 源代码"
    echo "(gdb) info registers                      # 查看寄存器"
    echo "(gdb) bt                                  # 查看调用栈"
    echo "(gdb) next                                # 单步执行 (不进入函数)"
    echo "(gdb) step                                # 单步执行 (进入函数)"
    echo "(gdb) print jiffies                       # 打印内核变量"
    echo "(gdb) x/16x \$esp                          # 查看栈内存"
    echo "(gdb) continue                            # 继续运行"
    echo "(gdb) quit                                # 退出 GDB"
    echo "============================================================"

    echo ""
    log_ok "第三部分验证完成"
}

# ============================================================================
# Part 4: 制作 Initramfs (Hello World) - i386
# ============================================================================
verify_part4() {
    log_section "第四部分：制作 Initramfs - i386 Hello World"

    cd "$LAB1_DIR"
    BZIMAGE="$KERNEL_DIR/arch/x86/boot/bzImage"
    if [ ! -f "$BZIMAGE" ]; then log_fail "bzImage 不存在"; return 1; fi

    echo "--- 4.1 创建 helloworld.c ---"
    cat > helloworld.c << 'CEOF'
#include <stdio.h>

void main()
{
    printf("lab1: Hello World\n");
    fflush(stdout);
    /* 让程序打印完后继续维持在用户态 */
    while(1);
}
CEOF
    cat helloworld.c
    echo ""

    echo "--- 4.2 交叉编译 helloworld (i386 静态链接) ---"
    if [ -x "$CROSS_INSTALL/bin/i686-linux-musl-gcc" ]; then
        echo "编译命令: i686-linux-musl-gcc -o helloworld -static helloworld.c"
        i686-linux-musl-gcc -o helloworld -static helloworld.c
    else
        log_fail "i686-linux-musl-gcc 不可用，请先运行: $0 musl"
        return 1
    fi

    file helloworld
    ls -lh helloworld
    echo ""

    echo "--- 4.3 用 cpio 打包 initramfs ---"
    echo helloworld | cpio -o --format=newc > hwinitramfs
    ls -lh hwinitramfs
    log_ok "hwinitramfs 已创建"
    echo ""

    echo "--- 4.4 启动内核并加载 helloworld initramfs ---"
    echo "命令: qemu-system-x86_64 -kernel .../bzImage -initrd hwinitramfs \\"
    echo "      -append 'console=ttyS0 rdinit=helloworld' -nographic"
    echo ""

    timeout 30 qemu-system-x86_64 -kernel "$BZIMAGE" \
        -initrd hwinitramfs \
        -append "console=ttyS0 rdinit=helloworld" \
        -nographic 2>&1 || true

    echo ""
    echo "--- 4.5 手动测试命令 ---"
    echo "============================================================"
    echo "# 编译 helloworld (i386 静态链接)"
    echo "cd $LAB1_DIR"
    echo "i686-linux-musl-gcc -o helloworld -static helloworld.c"
    echo "file helloworld    # 确认: ELF 32-bit LSB executable, Intel 80386, statically linked"
    echo ""
    echo "# 打包 initramfs"
    echo "echo helloworld | cpio -o --format=newc > hwinitramfs"
    echo ""
    echo "# 启动内核 + helloworld"
    echo "qemu-system-x86_64 -kernel $BZIMAGE -initrd hwinitramfs -append 'console=ttyS0 rdinit=helloworld' -nographic"
    echo "# 预期输出: 'lab1: Hello World'，然后程序 while(1) 挂起，Ctrl-A X 退出 QEMU"
    echo "============================================================"
    echo ""
    log_ok "第四部分验证完成"
}

verify_part5() {
    log_section "第五部分：编译并启动 Busybox (i386)"

    cd "$LAB1_DIR"
    BZIMAGE="$KERNEL_DIR/arch/x86/boot/bzImage"
    if [ ! -f "$BZIMAGE" ]; then log_fail "bzImage 不存在"; return 1; fi
    if [ ! -x "$CROSS_INSTALL/bin/i686-linux-musl-gcc" ]; then
        log_fail "i686-linux-musl-gcc 不可用"; return 1
    fi

    echo "--- 5.1 配置 Busybox (i386 静态交叉编译) ---"
    cd "$BUSYBOX_DIR"
    make distclean 2>/dev/null || true
    make defconfig 2>&1 | tail -1

    # 启用静态编译
    sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
    yes "" | make CROSS_COMPILE=i686-linux-musl- oldconfig 2>&1 | tail -3

    echo "关键配置:"
    grep -E 'CONFIG_STATIC=|CONFIG_CROSS_COMPILER_PREFIX=' .config
    echo ""

    echo "--- 5.2 编译 Busybox (CROSS_COMPILE=i686-linux-musl-) ---"
    make CROSS_COMPILE=i686-linux-musl- -j$(nproc) 2>&1 | tail -10

    if [ -f "busybox" ]; then
        log_ok "busybox 编译成功"
        file busybox
        ls -lh busybox
    else
        log_fail "busybox 编译失败"
        return 1
    fi
    echo ""

    echo "--- 5.3 安装 ---"
    make CROSS_COMPILE=i686-linux-musl- install 2>&1 | tail -3
    echo ""

    echo "--- 5.4 制作 initramfs ---"
    cd "$LAB1_DIR"
    rm -rf mybusybox
    mkdir -p mybusybox/{bin,sbin,etc,proc,sys,usr/{bin,sbin}}
    cp -a "$BUSYBOX_DIR/_install/"* mybusybox/

    cat > mybusybox/init << 'INITEOF'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
echo -e "\nBoot took $(cut -d' ' -f1 /proc/uptime) seconds\n"
exec /bin/sh
INITEOF
    chmod +x mybusybox/init

    cd mybusybox
    find . -print0 | cpio --null -ov --format=newc 2>/dev/null | gzip -9 > "$LAB1_DIR/initramfs-busybox-i386.cpio.gz"
    cd "$LAB1_DIR"

    log_ok "initramfs-busybox-i386.cpio.gz 已创建"
    ls -lh initramfs-busybox-i386.cpio.gz
    echo ""

    echo "--- 5.5 启动 Busybox i386 OS ---"
    echo "命令: qemu-system-x86_64 -kernel .../bzImage -initrd initramfs-busybox-i386.cpio.gz \\"
    echo "      -nographic -append 'console=ttyS0' -m 2048"
    echo ""

    {
        sleep 12
        echo "uname -a"
        sleep 2
        echo "cat /proc/cpuinfo | head -15"
        sleep 2
        echo "cat /proc/meminfo | head -10"
        sleep 2
        echo "ps"
        sleep 2
        echo "ls /"
        sleep 2
        echo "echo 'Busybox i386 OS test completed!'"
        sleep 2
        echo "poweroff -f"
        sleep 3
    } | timeout 60 qemu-system-x86_64 -kernel "$BZIMAGE" \
        -initrd "$LAB1_DIR/initramfs-busybox-i386.cpio.gz" \
        -nographic -append "console=ttyS0" -m 2048 2>&1 || true

    echo ""
    echo "--- 5.6 手动测试命令 ---"
    echo "============================================================"
    echo "# 编译 Busybox (i386 静态链接)"
    echo "cd $BUSYBOX_DIR"
    echo "make distclean && make defconfig"
    echo "sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config"
    echo "yes '' | make CROSS_COMPILE=i686-linux-musl- oldconfig"
    echo "make CROSS_COMPILE=i686-linux-musl- -j\$(nproc)"
    echo "make CROSS_COMPILE=i686-linux-musl- install"
    echo ""
    echo "# 制作 initramfs"
    echo "cd $LAB1_DIR && rm -rf mybusybox"
    echo "mkdir -p mybusybox/{bin,sbin,etc,proc,sys,usr/{bin,sbin}}"
    echo "cp -a $BUSYBOX_DIR/_install/* mybusybox/"
    echo "# 创建 init 脚本 (mount proc/sys, 启动 shell)"
    echo "cat > mybusybox/init << 'EOF'"
    echo "#!/bin/sh"
    echo "mount -t proc none /proc"
    echo "mount -t sysfs none /sys"
    echo "echo -e '\\nBoot took \$(cut -d\" \" -f1 /proc/uptime) seconds\\n'"
    echo "exec /bin/sh"
    echo "EOF"
    echo "chmod +x mybusybox/init"
    echo "cd mybusybox && find . -print0 | cpio --null -ov --format=newc 2>/dev/null | gzip -9 > $LAB1_DIR/initramfs-busybox-i386.cpio.gz"
    echo ""
    echo "# 启动 Busybox i386 OS (交互式)"
    echo "qemu-system-x86_64 -kernel $BZIMAGE -initrd $LAB1_DIR/initramfs-busybox-i386.cpio.gz -nographic -append 'console=ttyS0' -m 2048"
    echo "# 进入 shell 后可执行: uname -a, ls /, cat /proc/cpuinfo, ps, poweroff -f"
    echo "# 退出 QEMU: Ctrl-A X"
    echo "============================================================"
    echo ""
    log_ok "第五部分验证完成"
}

# ============================================================================
# Part 6: Linux 0.11 编译、启动和调试
# ============================================================================
verify_part6() {
    log_section "第六部分：Linux 0.11 内核编译、启动和调试"

    if [ ! -d "$LINUX011_DIR" ]; then
        log_fail "Linux 0.11 源码目录不存在"; return 1
    fi

    cd "$LINUX011_DIR"

    echo "--- 6.1 编译 Linux 0.11 (i386) ---"
    echo "使用交叉编译器: i386-elf-gcc ($(i386-elf-gcc --version 2>/dev/null | head -1))"
    echo "命令: make clean && make UNAME=Darwin"
    echo ""

    make clean 2>/dev/null || true
    make UNAME=Darwin 2>&1 | tail -20

    echo ""
    if [ -f "Image" ]; then
        log_ok "Linux 0.11 Image 已生成"
        file Image
        ls -lh Image
    else
        log_fail "Image 编译失败"
        return 1
    fi

    if [ -f "tools/system" ]; then
        log_ok "符号表 tools/system"
        file tools/system
    fi
    echo ""

    echo "--- 6.2 启动 Linux 0.11 ---"
    if [ -f "hdc-0.11.img" ]; then
        echo "命令: qemu-system-x86_64 -m 16 -boot a -fda Image -hda hdc-0.11.img -nographic -serial mon:stdio"
        echo ""
        timeout 15 qemu-system-x86_64 -m 16 -boot a -fda Image -hda hdc-0.11.img \
            -nographic -serial mon:stdio 2>&1 || true
    else
        log_info "hdc-0.11.img 不存在，仅验证编译"
    fi

    echo ""
    echo "--- 6.3 手动测试命令 ---"
    echo "============================================================"
    echo ""
    echo "# 编译 Linux 0.11"
    echo "cd $LINUX011_DIR"
    echo "export PATH=$CROSS_INSTALL/bin:\$PATH"
    echo "make clean && make UNAME=Darwin"
    echo "file Image          # DOS/MBR boot sector"
    echo "file tools/system   # ELF 32-bit LSB executable, Intel 80386"
    echo ""
    echo "# 启动 Linux 0.11 (交互式)"
    echo "qemu-system-x86_64 -m 16 -boot a -fda Image -hda hdc-0.11.img -nographic -serial mon:stdio"
    echo "# 退出 QEMU: Ctrl-A X"
    echo ""
    echo "# GDB 调试 Linux 0.11"
    echo "# 终端1: 启动 QEMU，冻结 CPU 等待 GDB 连接"
    echo "qemu-system-x86_64 -m 16 -boot a -fda Image -hda hdc-0.11.img -s -S -nographic -serial mon:stdio"
    echo ""
    echo "# 终端2: 交互式 GDB 调试"
    echo "x86_64-elf-gdb"
    echo "(gdb) target remote :1234                # 连接 QEMU gdb stub"
    echo "(gdb) symbol-file $LINUX011_DIR/tools/system  # 加载 Linux 0.11 符号表"
    echo "(gdb) break main                          # 在 main 函数设置断点"
    echo "(gdb) continue                            # 运行到 main"
    echo "(gdb) list                                # 查看 main 源代码"
    echo "(gdb) info registers                      # 查看寄存器"
    echo "(gdb) bt                                  # 查看调用栈"
    echo "(gdb) break mem_init                      # 在 mem_init 设断点"
    echo "(gdb) continue                            # 运行到 mem_init"
    echo "(gdb) next                                # 单步执行"
    echo "(gdb) print memory_end                    # 打印内核变量"
    echo "(gdb) quit                                # 退出 GDB"
    echo "============================================================"

    log_ok "第六部分验证完成"
}

# ============================================================================
# Part 7: 认识麒麟操作系统
# ============================================================================
verify_part7() {
    log_section "第七部分：认识麒麟操作系统"

    echo "=== 7.1 系统基本信息 ==="
    echo "--- 操作系统版本 ---"
    cat /etc/os-release
    echo ""
    echo "--- 内核版本和CPU架构 ---"
    uname -a
    echo ""
    echo "--- CPU信息 ---"
    cat /proc/cpuinfo
    echo ""
    echo "--- 内存信息 ---"
    free -h
    echo ""
    echo "--- 磁盘信息 ---"
    df -h
    echo ""

    echo "=== 7.2 包管理器 (yum/dnf vs apt) ==="
    echo "--- 已安装的 gcc 相关包 ---"
    rpm -qa | grep gcc
    echo ""
    echo "--- 软件源 ---"
    ls /etc/yum.repos.d/
    echo ""

    echo "=== 7.3 CPU架构 ==="
    uname -m
    lscpu
    echo ""
    gcc -dumpmachine
    echo ""

    log_ok "第七部分验证完成"
}

# ============================================================================
# Part 8: 探索麒麟OS内核
# ============================================================================
verify_part8() {
    log_section "第八部分：探索麒麟OS内核"

    echo "=== 8.1 /proc虚拟文件系统 ==="
    echo "--- 内核版本 ---"
    cat /proc/version
    echo ""
    echo "--- 系统运行时间 ---"
    cat /proc/uptime
    echo ""
    echo "--- 内存使用详情 ---"
    cat /proc/meminfo | head -20
    echo ""
    echo "--- 当前进程信息 ---"
    cat /proc/self/status
    echo ""
    echo "--- 支持的文件系统 ---"
    cat /proc/filesystems
    echo ""
    echo "--- 内核启动命令行参数 ---"
    cat /proc/cmdline
    echo ""
    echo "--- /proc/1/status (init进程) ---"
    cat /proc/1/status 2>/dev/null || echo "(需要root权限)"
    echo ""
    echo "--- 占用内存最多的前5个进程 ---"
    ps aux --sort=-%mem | head -6
    echo ""

    echo "=== 8.2 系统启动日志 ==="
    journalctl -k --no-pager 2>/dev/null | head -50 || echo "(journalctl 不可用)"
    echo ""
    echo "--- 启动相关 ---"
    journalctl -k --no-pager 2>/dev/null | grep -i "boot" | head -10
    echo ""
    echo "--- CPU初始化 ---"
    journalctl -k --no-pager 2>/dev/null | grep -i "cpu" | head -10
    echo ""
    echo "--- 内存初始化 ---"
    journalctl -k --no-pager 2>/dev/null | grep -i "memory" | head -10
    echo ""

    echo "=== 8.3 内核模块 ==="
    lsmod | head -20
    echo ""
    echo "--- ext4模块信息 ---"
    modinfo ext4 2>/dev/null | head -15 || echo "ext4 不可用"
    echo ""

    MYMOD_DIR="$LAB1_DIR/mymodule"
    if [ -d "$MYMOD_DIR" ] && [ -f "$MYMOD_DIR/hello_module.ko" ]; then
        echo "--- Hello World 内核模块 ---"
        file "$MYMOD_DIR/hello_module.ko"
        echo ""
        echo "加载测试 (需要sudo):"
        echo "  sudo insmod $MYMOD_DIR/hello_module.ko"
        echo "  journalctl -k --no-pager | tail -5"
        echo "  sudo rmmod hello_module"
    fi
    echo ""

    echo "=== 8.4 系统调用观察 ==="
    echo "--- strace ls /tmp ---"
    strace ls /tmp 2>&1 | head -30
    echo ""
    echo "--- 系统调用统计: strace -c ls /tmp ---"
    strace -c ls /tmp 2>&1
    echo ""

    cd "$LAB1_DIR"
    cat > hello_strace.c << 'HEOF'
#include <stdio.h>
int main() {
    printf("Hello from Kylin OS!\n");
    return 0;
}
HEOF
    gcc -o hello_strace hello_strace.c -static
    echo "--- strace ./hello_strace 系统调用统计 ---"
    strace -c ./hello_strace 2>&1
    echo ""

    echo "=== 8.5 QEMU跨架构 ==="
    ls /usr/bin/qemu-system-* 2>/dev/null
    echo ""

    log_ok "第八部分验证完成"
}

# ============================================================================
# 主函数
# ============================================================================
main() {
    echo "============================================================================"
    echo "  Lab1 i386 完整验证 - 麒麟操作系统 (ARM64 → i386 交叉编译)"
    echo "  时间: $(date)"
    echo "  系统: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
    echo "  架构: $(uname -m) (宿主) → i386 (目标)"
    echo "============================================================================"

    build_musl  2>&1 | tee "$RESULTS_DIR/step0_musl.log"
    verify_part1 2>&1 | tee "$RESULTS_DIR/part1_env.log"
    verify_part2 2>&1 | tee "$RESULTS_DIR/part2_kernel.log"
    verify_part3 2>&1 | tee "$RESULTS_DIR/part3_boot_gdb.log"
    verify_part4 2>&1 | tee "$RESULTS_DIR/part4_helloworld.log"
    verify_part5 2>&1 | tee "$RESULTS_DIR/part5_busybox.log"
    verify_part6 2>&1 | tee "$RESULTS_DIR/part6_linux011.log"
    verify_part7 2>&1 | tee "$RESULTS_DIR/part7_kylin.log"
    verify_part8 2>&1 | tee "$RESULTS_DIR/part8_explore.log"

    echo ""
    log_section "验证总结"
    echo "所有结果保存在: $RESULTS_DIR/"
    ls -lh "$RESULTS_DIR/"
    echo ""
    echo "完成时间: $(date)"
}

# ======================== 入口 ========================
if [ "${1:-}" != "" ]; then
    case "$1" in
        musl|0) build_musl  2>&1 | tee "$RESULTS_DIR/step0_musl.log" ;;
        1) verify_part1 2>&1 | tee "$RESULTS_DIR/part1_env.log" ;;
        2) verify_part2 2>&1 | tee "$RESULTS_DIR/part2_kernel.log" ;;
        3) verify_part3 2>&1 | tee "$RESULTS_DIR/part3_boot_gdb.log" ;;
        4) verify_part4 2>&1 | tee "$RESULTS_DIR/part4_helloworld.log" ;;
        5) verify_part5 2>&1 | tee "$RESULTS_DIR/part5_busybox.log" ;;
        6) verify_part6 2>&1 | tee "$RESULTS_DIR/part6_linux011.log" ;;
        7) verify_part7 2>&1 | tee "$RESULTS_DIR/part7_kylin.log" ;;
        8) verify_part8 2>&1 | tee "$RESULTS_DIR/part8_explore.log" ;;
        all) main ;;
        *) echo "用法: $0 [musl|1-8|all]" ;;
    esac
else
    main
fi
