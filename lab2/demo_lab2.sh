#!/bin/bash
# ============================================================================
# Lab2 课堂展示脚本 - 本机/麒麟虚拟机通用
# 用法: bash demo_lab2.sh [命令]
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB2_DIR="$SCRIPT_DIR"
SRC_DIR="$LAB2_DIR/src"
ASG_DIR="$LAB2_DIR/assignment"
CROSS_TOOLS="$LAB2_DIR/../lab1/cross-tools/install/bin"
CROSS_LD="$CROSS_TOOLS/i686-elf-ld"
GDB_X64="$CROSS_TOOLS/x86_64-elf-gdb"
GDB_I386="$CROSS_TOOLS/i686-elf-gdb"
QEMU="$(command -v qemu-system-i386 2>/dev/null || command -v qemu-system-x86_64 2>/dev/null || echo qemu-system-x86_64)"
SSH_HOST="${LAB2_SSH_HOST:-cpf@127.0.0.1}"
SSH_PORT="${LAB2_SSH_PORT:-722}"
SSH_CMD="ssh -p $SSH_PORT $SSH_HOST"
REMOTE_DEMO_SCRIPT="${LAB2_REMOTE_DEMO_SCRIPT:-/home/cpf/OSLab-i386-2026/lab2/demo_lab2.sh}"
SCP_CMD="scp -P $SSH_PORT"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

VNC_DISPLAY=":0"
VNC_PORT=5900
VNC_PASSWORD="1"
QEMU_MON_SOCK="/tmp/qemu-mon.sock"

SPICE_SOCK="/tmp/qemu-spice.sock"
SPICE_PORT=5930
LOCAL_VNC_PORT="${LAB2_LOCAL_VNC_PORT:-5901}"
LOCAL_SPICE_PORT="${LAB2_LOCAL_SPICE_PORT:-5931}"
SPICE_CLIENT=""
RELAY_PID=""
RELAY_LOCAL_PORT=""

show_help() {
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}  Lab2 课堂展示脚本 - 本机/麒麟虚拟机通用${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    echo -e "${GREEN}编译命令:${NC}"
    echo "  bash demo_lab2.sh compile <name>    编译单个 asm (如 a1_helloworld)"
    echo "  bash demo_lab2.sh compile-all       编译所有 asm 文件"
    echo ""
    echo -e "${GREEN}VNC 查看 (适合麒麟虚拟机 / 无本地图形环境):${NC}"
    echo "  bash demo_lab2.sh vnc <name>        启动 QEMU + VNC (密码: $VNC_PASSWORD, 端口自动选择)"
    echo "  bash demo_lab2.sh vnc-snake         启动贪吃蛇 + VNC"
    echo "  bash demo_lab2.sh vnc-stop          停止 QEMU"
    echo "  bash demo_lab2.sh remote-vnc <name> 在 Mac 上一键 SSH 启动并打开 VNC（可显示并输入）"
    echo "  bash demo_lab2.sh remote-vnc-snake  在 Mac 上一键 SSH 启动贪吃蛇并打开 VNC（可显示并输入）"
    echo ""
    echo -e "${GREEN}VGA 显存验证 (无需图形界面):${NC}"
    echo "  bash demo_lab2.sh vga <name>        启动并 dump VGA 显存"
    echo "  bash demo_lab2.sh vga-all           验证所有程序的 VGA 输出"
    echo ""
    echo -e "${GREEN}GDB 调试:${NC}"
    echo "  bash demo_lab2.sh gdb-start <name>  启动 QEMU 等待 GDB 连接"
    echo "  bash demo_lab2.sh gdb-connect       连接 GDB 到 QEMU"
    echo "  bash demo_lab2.sh gdb-auto <name>   自动 GDB 调试演示"
    echo ""
    echo -e "${GREEN}Assignment 3:${NC}"
    echo "  bash demo_lab2.sh a3-compile        编译 student.asm (ELF32)"
    echo ""
    echo -e "${GREEN}SPICE 远程查看 (需 spicy 客户端):${NC}"
    echo "  bash demo_lab2.sh spice <name>      启动 QEMU + SPICE (端口自动选择)"
    echo "  bash demo_lab2.sh spice-snake       启动贪吃蛇 + SPICE"
    echo "  bash demo_lab2.sh spice-stop        停止 QEMU"
    echo "  bash demo_lab2.sh remote-spice <name> 在 Mac 上一键 SSH 启动并打开 SPICE（可显示并输入）"
    echo "  bash demo_lab2.sh remote-spice-snake  在 Mac 上一键 SSH 启动贪吃蛇并打开 SPICE（可显示并输入）"
    echo "  bash demo_lab2.sh remote-stop         停止远端 QEMU 与本地中继"
    echo ""
    echo -e "${GREEN}其他:${NC}"
    echo "  bash demo_lab2.sh run <name>        本机直接运行 QEMU (需本地图形界面)"
    echo "  bash demo_lab2.sh run-snake         本机直接运行贪吃蛇 (需本地图形界面)"
    echo "  bash demo_lab2.sh show <name>       显示 asm 源码"
    echo "  bash demo_lab2.sh list              列出所有文件"
    echo ""
    echo -e "${GREEN}可用的 <name>:${NC}"
    echo "  a1_helloworld  a1_studentid  a1_loop"
    echo "  a2_cursor      a2_int10h     a2_keyboard"
    echo "  a4_spiral      mbr_snake"
    echo ""
    echo -e "${YELLOW}=== 推荐用法 1：本机直接运行 ===${NC}"
    echo "  在当前机器有图形界面时，直接执行:"
    echo "    bash demo_lab2.sh run-snake"
    echo ""
    echo -e "${YELLOW}=== 推荐用法 2：麒麟虚拟机运行，Mac 上通过 VNC 观察 ===${NC}"
    echo "  直接在 Mac 上执行:"
    echo "    bash demo_lab2.sh remote-vnc-snake"
    echo "  脚本会自动: SSH 到虚拟机启动 QEMU、解析 VNC 端口、启动中继并打开客户端"
    echo "  这样既能看到远端窗口，也能把本地键盘输入发送给贪吃蛇程序"
    echo ""
    echo -e "${YELLOW}=== SPICE 使用方法 (图形桌面或 SSH 中继) ===${NC}"
    echo "  方式A - 麒麟图形桌面:"
    echo "    bash demo_lab2.sh spice <name>"
    echo "    spicy -h 127.0.0.1 -p $SPICE_PORT"
    echo "  方式B - SSH 远程 (Mac, 需 brew install virt-viewer):"
    echo "    1. 直接执行: bash demo_lab2.sh remote-spice <name>"
    echo "    2. 或分步: 远端 spice <name> + 本地 relay/client"
    echo "  SPICE 和 VNC 都不仅传回图形画面，也负责把本地输入转发给远端 QEMU 窗口"
}

# ---- 编译 ----
do_compile() {
    local name=$1
    local asm="$SRC_DIR/${name}.asm"
    [ ! -f "$asm" ] && echo "文件不存在: $asm" && return 1

    echo -e "${BLUE}--- 编译 $name ---${NC}"
    echo "  nasm -f bin $asm -o $SRC_DIR/${name}.bin"
    nasm -f bin "$asm" -o "$SRC_DIR/${name}.bin"
    echo -e "${GREEN}[OK]${NC} ${name}.bin ($(wc -c < "$SRC_DIR/${name}.bin") bytes)"

    # 检查 MBR 签名
    local sig=$(xxd -s 510 -l 2 -p "$SRC_DIR/${name}.bin")
    [ "$sig" = "55aa" ] && echo -e "${GREEN}[OK]${NC} MBR 签名 0x55AA" || echo -e "${YELLOW}[WARN]${NC} MBR 签名: 0x$sig"

    # 创建磁盘镜像
    qemu-img create "$SRC_DIR/${name}.img" 10m 2>/dev/null
    dd if="$SRC_DIR/${name}.bin" of="$SRC_DIR/${name}.img" bs=512 count=1 seek=0 conv=notrunc 2>/dev/null
    echo -e "${GREEN}[OK]${NC} ${name}.img 已创建"

    # 生成符号表
    if [ -f "$CROSS_LD" ]; then
        sed 's/^org 0x7c00/; org 0x7c00/' "$asm" > "/tmp/${name}_noorg.asm"
        nasm -o "/tmp/${name}.o" -g -f elf32 "/tmp/${name}_noorg.asm" 2>/dev/null
        if [ $? -eq 0 ]; then
            $CROSS_LD -o "$SRC_DIR/${name}.symbol" -melf_i386 -N "/tmp/${name}.o" -Ttext 0x7c00 2>/dev/null
            [ $? -eq 0 ] && echo -e "${GREEN}[OK]${NC} ${name}.symbol 符号表已生成"
        fi
        rm -f "/tmp/${name}_noorg.asm" "/tmp/${name}.o"
    fi
    echo ""
}

do_compile_all() {
    for f in $SRC_DIR/a1_*.asm $SRC_DIR/a2_*.asm $SRC_DIR/a4_*.asm $SRC_DIR/mbr_snake.asm; do
        [ -f "$f" ] && do_compile $(basename "$f" .asm)
    done
    # snake 主程序
    if [ -f "$SRC_DIR/snake.asm" ]; then
        echo -e "${BLUE}--- 编译 snake.asm ---${NC}"
        nasm -f bin "$SRC_DIR/snake.asm" -o "$SRC_DIR/snake.bin" 2>&1
        echo -e "${GREEN}[OK]${NC} snake.bin ($(wc -c < "$SRC_DIR/snake.bin") bytes)"
        dd if=/dev/zero of="$SRC_DIR/snake.img" bs=512 count=2880 2>/dev/null
        dd if="$SRC_DIR/mbr_snake.bin" of="$SRC_DIR/snake.img" bs=512 count=1 conv=notrunc 2>/dev/null
        dd if="$SRC_DIR/snake.bin" of="$SRC_DIR/snake.img" bs=512 seek=1 conv=notrunc 2>/dev/null
        echo -e "${GREEN}[OK]${NC} snake.img 完整磁盘镜像已创建"
    fi
}

# ============================================================================
# VNC 远程查看 (SSH 友好)
# 原理: QEMU 编译时无 gtk/sdl 后端，无法直接弹出窗口
#       使用 -vnc :0,password=on 启动 VNC 服务，通过 SSH 管道中继到本地
#       macOS 自带的"屏幕共享"客户端即可连接查看
# ============================================================================
qemu_vnc_set_password() {
    # 通过 QEMU monitor unix socket 设置 VNC 密码
    python3 - "$QEMU_MON_SOCK" "$VNC_PASSWORD" << 'PYEOF'
import socket, time, sys
sock_path, pwd = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sock_path)
time.sleep(0.3)
s.recv(4096)
s.sendall(f'change vnc password {pwd}\r\n'.encode())
time.sleep(0.5)
resp = s.recv(4096).decode(errors='replace')
s.close()
PYEOF
}

vnc_display_to_port() {
    local display_num=${1#:}
    echo $((5900 + display_num))
}

start_qemu_with_vnc() {
    local img="$1"
    local if_type="$2"
    local display
    local port
    local drive_arg="file=${img},format=raw"

    if [ -n "$if_type" ]; then
        drive_arg="${drive_arg},if=${if_type}"
    fi

    for display in :0 :1 :2; do
        port=$(vnc_display_to_port "$display")
        rm -f "$QEMU_MON_SOCK"
        "$QEMU" -drive "$drive_arg" \
            -display none -vnc ${display},password=on \
            -monitor unix:${QEMU_MON_SOCK},server,nowait \
            -daemonize 2>&1
        if [ $? -eq 0 ]; then
            VNC_DISPLAY="$display"
            VNC_PORT="$port"
            return 0
        fi
    done

    return 1
}

start_qemu_with_spice() {
    local img="$1"
    local if_type="$2"
    local port
    local drive_arg="file=${img},format=raw"

    if [ -n "$if_type" ]; then
        drive_arg="${drive_arg},if=${if_type}"
    fi

    for port in 5930 5931 5932; do
        rm -f "$SPICE_SOCK"
        "$QEMU" -drive "$drive_arg" \
            -display none \
            -spice port=${port},disable-ticketing=on \
            -daemonize 2>&1
        if [ $? -eq 0 ]; then
            SPICE_PORT="$port"
            return 0
        fi
    done

    return 1
}

detect_spice_client() {
    if command -v remote-viewer >/dev/null 2>&1; then
        SPICE_CLIENT="remote-viewer"
        return 0
    fi
    if command -v spicy >/dev/null 2>&1; then
        SPICE_CLIENT="spicy"
        return 0
    fi

    SPICE_CLIENT=""
    return 1
}

stop_local_relays() {
    local pidfile
    local pid

    for pidfile in /tmp/lab2_vnc_relay.pid /tmp/lab2_spice_relay.pid; do
        if [ -f "$pidfile" ]; then
            pid=$(cat "$pidfile" 2>/dev/null)
            if [ -n "$pid" ]; then
                kill "$pid" 2>/dev/null
            fi
            rm -f "$pidfile"
        fi
    done

    pkill -f "lab2_vnc_relay_inner" 2>/dev/null
    pkill -f "lab2_spice_relay_inner" 2>/dev/null
}

start_ssh_tcp_relay() {
    local tag="$1"
    local base_local_port="$2"
    local remote_port="$3"
    local pidfile="/tmp/${tag}_relay.pid"
    local local_port
    local pid
    local found_port=""

    if [ -f "$pidfile" ]; then
        pid=$(cat "$pidfile" 2>/dev/null)
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null
            sleep 1
        fi
        rm -f "$pidfile"
    fi

    pkill -f "${tag}_relay_inner" 2>/dev/null
    sleep 1

    for local_port in "$base_local_port" $((base_local_port + 1)) $((base_local_port + 2)) $((base_local_port + 3)); do
        if ! lsof -nP -iTCP:"$local_port" -sTCP:LISTEN >/dev/null 2>&1; then
            found_port="$local_port"
            break
        fi
    done

    if [ -z "$found_port" ]; then
        echo -e "${RED}[ERROR] 未找到可用的本地中继端口${NC}"
        return 1
    fi

    local_port="$found_port"

    python3 - "$SSH_PORT" "$SSH_HOST" "$local_port" "$remote_port" "$tag" <<PYEOF &
# ${tag}_relay_inner
import subprocess, socket, threading, sys, signal

ssh_port, ssh_host, local_port, remote_port, tag = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5]
ssh_cmd = ['ssh', '-p', ssh_port, ssh_host, 'nc', '127.0.0.1', remote_port]

def relay(src, dst):
    try:
        while True:
            if hasattr(src, 'recv'):
                data = src.recv(65536)
            elif hasattr(src, 'read1'):
                data = src.read1(65536)
            else:
                data = src.read(65536)
            if not data:
                break
            if hasattr(dst, 'sendall'):
                dst.sendall(data)
            else:
                dst.write(data)
                dst.flush()
    except Exception:
        pass

def handle(client, addr):
    print(f'[+] {tag} client: {addr}', flush=True)
    proc = subprocess.Popen(ssh_cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    t1 = threading.Thread(target=relay, args=(client, proc.stdin), daemon=True)
    t2 = threading.Thread(target=relay, args=(proc.stdout, client), daemon=True)
    t1.start(); t2.start()
    t1.join(); t2.join()
    proc.terminate()
    client.close()
    print(f'[-] {tag} disconnected: {addr}', flush=True)

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('127.0.0.1', local_port))
server.listen(5)
print(f'{tag} relay listening on 127.0.0.1:{local_port}', flush=True)
signal.signal(signal.SIGINT, lambda *a: (server.close(), sys.exit(0)))

while True:
    try:
        client, addr = server.accept()
        threading.Thread(target=handle, args=(client, addr), daemon=True).start()
    except OSError:
        break
PYEOF

    RELAY_PID=$!
    RELAY_LOCAL_PORT="$local_port"
    echo "$RELAY_PID" > "$pidfile"
    sleep 1

    if kill -0 "$RELAY_PID" 2>/dev/null; then
        echo -e "${GREEN}[OK]${NC} ${tag} 中继已启动 (PID: $RELAY_PID, 本地端口: $local_port, 远端端口: $remote_port)"
        return 0
    fi

    rm -f "$pidfile"
    echo -e "${RED}[ERROR] ${tag} 中继启动失败${NC}"
    return 1
}

open_spice_client() {
    local local_port="$1"

    if ! detect_spice_client; then
        echo -e "${YELLOW}[WARN] 未找到 SPICE 客户端${NC}"
        echo "  可安装: brew install virt-viewer 或 brew install spice-gtk"
        echo "  手动连接: remote-viewer spice://127.0.0.1:${local_port}"
        return 0
    fi

    if [ "$SPICE_CLIENT" = "remote-viewer" ]; then
        remote-viewer "spice://127.0.0.1:${local_port}" >/dev/null 2>&1 &
    else
        spicy -h 127.0.0.1 -p "$local_port" >/dev/null 2>&1 &
    fi
}

do_remote_stop() {
    stop_local_relays
    $SSH_CMD "pkill -9 qemu-system 2>/dev/null || pkill -9 -f qemu-system 2>/dev/null" 2>/dev/null
    echo -e "${GREEN}[OK] 已停止远端 QEMU 与本地中继${NC}"
}

sync_remote_view_files() {
    local name="$1"
    local remote_lab2_dir
    local local_file
    local remote_file

    remote_lab2_dir=$(dirname "$REMOTE_DEMO_SCRIPT")

    $SSH_CMD "mkdir -p '$remote_lab2_dir/src'" >/dev/null 2>&1 || return 1

    $SCP_CMD "$SCRIPT_DIR/demo_lab2.sh" "$SSH_HOST:$REMOTE_DEMO_SCRIPT" >/dev/null || return 1

    if [ "$name" = "snake" ]; then
        for local_file in "$SRC_DIR/mbr_snake.asm" "$SRC_DIR/snake.asm"; do
            remote_file="$SSH_HOST:$remote_lab2_dir/src/$(basename "$local_file")"
            $SCP_CMD "$local_file" "$remote_file" >/dev/null || return 1
        done
    else
        local_file="$SRC_DIR/${name}.asm"
        if [ -f "$local_file" ]; then
            remote_file="$SSH_HOST:$remote_lab2_dir/src/$(basename "$local_file")"
            $SCP_CMD "$local_file" "$remote_file" >/dev/null || return 1
        fi
    fi

    return 0
}

do_remote_view() {
    local backend="$1"
    local name="$2"
    local backend_upper
    local remote_cmd
    local remote_prepare_cmd
    local output
    local remote_port
    local local_port
    local port_pattern
    local tag

    if [ -z "$name" ]; then
        echo -e "${RED}[ERROR] 缺少程序名${NC}"
        return 1
    fi

    backend_upper=$(printf '%s' "$backend" | tr '[:lower:]' '[:upper:]')

    case "$backend" in
        vnc)
            remote_port=5900
            local_port="$LOCAL_VNC_PORT"
            port_pattern='VNC 监听端口 \([0-9][0-9]*\)'
            tag='lab2_vnc'
            ;;
        spice)
            remote_port=5930
            local_port="$LOCAL_SPICE_PORT"
            port_pattern='SPICE TCP 端口 \([0-9][0-9]*\)'
            tag='lab2_spice'
            ;;
        *)
            echo -e "${RED}[ERROR] 不支持的查看方式: $backend${NC}"
            return 1
            ;;
    esac

    if [ "$name" = "snake" ]; then
        remote_prepare_cmd="bash $REMOTE_DEMO_SCRIPT compile-all"
        remote_cmd="$backend-snake"
    else
        remote_prepare_cmd="bash $REMOTE_DEMO_SCRIPT compile $name"
        remote_cmd="$backend $name"
    fi

    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}  Lab2 远程查看: ${backend} / ${name}${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""

    echo -e "${BLUE}[0/3] 同步本地脚本与源码到远端 ...${NC}"
    if ! sync_remote_view_files "$name"; then
        echo -e "${RED}[ERROR] 同步远端文件失败${NC}"
        return 1
    fi

    echo -e "${BLUE}[1/3] 远端编译并启动 QEMU + ${backend_upper} ...${NC}"

    output=$($SSH_CMD "pkill -9 qemu 2>/dev/null; sleep 1; $remote_prepare_cmd >/tmp/lab2_remote_prepare.log 2>&1 && bash $REMOTE_DEMO_SCRIPT $remote_cmd" 2>&1)
    echo "$output" | grep -v '^Authorized\|^$'

    if echo "$output" | grep -q '\[ERROR\]'; then
        echo -e "${RED}[ERROR] 远端 QEMU 启动失败${NC}"
        echo -e "${YELLOW}--- 远端编译日志 ---${NC}"
        $SSH_CMD "tail -n 60 /tmp/lab2_remote_prepare.log 2>/dev/null" 2>/dev/null
        return 1
    fi

    if ! $SSH_CMD "pgrep -f qemu-system" >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] 远端 QEMU 进程未找到${NC}"
        return 1
    fi

    remote_port=$(echo "$output" | sed -n "s/.*${port_pattern}.*/\\1/p" | tail -n 1)
    [ -z "$remote_port" ] && remote_port=$([ "$backend" = "vnc" ] && echo 5900 || echo 5930)

    echo -e "${BLUE}[2/3] 启动本地 ${backend_upper} 中继 ...${NC}"
    start_ssh_tcp_relay "$tag" "$local_port" "$remote_port" || return 1

    echo -e "${BLUE}[3/3] 打开本地客户端 ...${NC}"
    if [ "$backend" = "vnc" ]; then
        echo -e "${YELLOW}  VNC 密码: $VNC_PASSWORD${NC}"
        open "vnc://127.0.0.1:${RELAY_LOCAL_PORT}"
    else
        open_spice_client "$RELAY_LOCAL_PORT"
    fi

    echo ""
    echo -e "${GREEN}=== ${backend_upper} 已启动 ===${NC}"
    echo -e "  停止: bash demo_lab2.sh remote-stop"
}

do_vnc() {
    local name=$1
    local img="$SRC_DIR/${name}.img"
    [ ! -f "$img" ] && echo -e "${RED}镜像不存在: $img，先运行 compile${NC}" && return 1

    pkill -9 -f qemu-system 2>/dev/null
    sleep 1
    rm -f "$QEMU_MON_SOCK"

    echo -e "${BLUE}--- 启动 VNC: $name ---${NC}"
    echo -e "  $QEMU -drive file=$img,format=raw"
    echo -e "  -display none -vnc ${VNC_DISPLAY},password=on"

    start_qemu_with_vnc "$img"

    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERROR] QEMU 启动失败${NC}"
        return 1
    fi

    sleep 1
    qemu_vnc_set_password

    echo ""
    echo -e "${GREEN}[OK] QEMU 已启动，VNC 监听端口 $VNC_PORT${NC}"
    echo ""
    echo -e "${CYAN}=== 连接方法 ===${NC}"
    echo -e "  ${YELLOW}1. 在本地 Mac 终端运行 VNC 中继:${NC}"
    echo -e "     python3 vnc_relay.py"
    echo -e "  ${YELLOW}2. 打开 macOS VNC 客户端:${NC}"
    echo -e "     open vnc://127.0.0.1:5901"
    echo -e "  ${YELLOW}3. 输入密码: ${VNC_PASSWORD}${NC}"
    echo ""
    echo -e "  停止: bash demo_lab2.sh vnc-stop"
}

do_vnc_snake() {
    local img="$SRC_DIR/snake.img"
    [ ! -f "$img" ] && [ -f "$SRC_DIR/snake_game.img" ] && img="$SRC_DIR/snake_game.img"
    [ ! -f "$img" ] && echo -e "${RED}snake 镜像不存在，请先在 $SRC_DIR 运行 compile-all 或 make${NC}" && return 1

    pkill -9 -f qemu-system 2>/dev/null
    sleep 1
    rm -f "$QEMU_MON_SOCK"

    echo -e "${BLUE}--- 启动 VNC: 贪吃蛇 ---${NC}"
    start_qemu_with_vnc "$img" "floppy"

    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERROR] QEMU 启动失败${NC}"
        return 1
    fi

    sleep 1
    qemu_vnc_set_password

    echo ""
    echo -e "${GREEN}[OK] 贪吃蛇已启动，VNC 监听端口 $VNC_PORT${NC}"
    echo -e "  连接后可用方向键操控蛇移动"
    echo -e "  VNC 密码: ${VNC_PASSWORD}"
}

do_vnc_stop() {
    pkill -9 -f qemu-system 2>/dev/null
    rm -f "$QEMU_MON_SOCK"
    echo -e "${GREEN}[OK] QEMU 已停止${NC}"
}

# ============================================================================
# SPICE 远程查看
# 原理: 启动 QEMU + SPICE 服务 (unix socket 或 TCP 端口)
#       方式A: 麒麟图形桌面用 spicy 直连 unix socket
#       方式B: SSH 远程用 TCP 端口 + SSH 管道中继到本地
# ============================================================================
do_spice() {
    local name=$1
    local img="$SRC_DIR/${name}.img"
    [ ! -f "$img" ] && echo -e "${RED}镜像不存在: $img，先运行 compile${NC}" && return 1

    pkill -9 -f qemu-system 2>/dev/null
    sleep 1
    rm -f "$SPICE_SOCK"

    echo -e "${BLUE}--- 启动 SPICE: $name ---${NC}"
    echo -e "  $QEMU -drive file=$img,format=raw"
    echo -e "  -display none -spice port=${SPICE_PORT},disable-ticketing=on"

    # QEMU 8.2 不支持 dual -spice 或 unix+tcp 合写，统一使用 TCP 端口
    start_qemu_with_spice "$img"

    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERROR] QEMU 启动失败${NC}"
        return 1
    fi

    sleep 1
    echo ""
    echo -e "${GREEN}[OK] QEMU 已启动，SPICE TCP 端口 $SPICE_PORT${NC}"
    echo ""
    echo -e "${CYAN}=== 连接方法 ===${NC}"
    echo -e "  ${YELLOW}方式A - 麒麟图形桌面:${NC}"
    echo -e "    spicy -h 127.0.0.1 -p $SPICE_PORT"
    echo -e "  ${YELLOW}方式B - SSH 远程 (Mac):${NC}"
    echo -e "    1. 本端: python3 spice_relay.py     # 启动 SPICE 中继"
    echo -e "    2. 本端: remote-viewer spice://127.0.0.1:5931"
    echo -e "       或:   bash lab2_spice.sh          # 一键脚本"
    echo ""
    echo -e "  停止: bash demo_lab2.sh spice-stop"
}

do_spice_snake() {
    local img="$SRC_DIR/snake.img"
    [ ! -f "$img" ] && [ -f "$SRC_DIR/snake_game.img" ] && img="$SRC_DIR/snake_game.img"
    [ ! -f "$img" ] && echo -e "${RED}snake 镜像不存在，请先在 $SRC_DIR 运行 compile-all 或 make${NC}" && return 1

    pkill -9 -f qemu-system 2>/dev/null
    sleep 1

    echo -e "${BLUE}--- 启动 SPICE: 贪吃蛇 ---${NC}"

    start_qemu_with_spice "$img" "floppy"

    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERROR] QEMU 启动失败${NC}"
        return 1
    fi

    sleep 1
    echo -e "${GREEN}[OK] 贪吃蛇已启动，SPICE TCP 端口 $SPICE_PORT${NC}"
    echo -e "  连接后可用方向键操控蛇移动"
    echo -e "  图形桌面: spicy -h 127.0.0.1 -p $SPICE_PORT"
    echo -e "  SSH 远程: python3 spice_relay.py + remote-viewer"
}

do_spice_stop() {
    pkill -9 -f qemu-system 2>/dev/null
    rm -f "$SPICE_SOCK" 2>/dev/null
    echo -e "${GREEN}[OK] QEMU 已停止${NC}"
}

# ---- QEMU 运行 (需本地图形) ----
do_run() {
    local name=$1
    local img="$SRC_DIR/${name}.img"
    [ ! -f "$img" ] && echo "镜像不存在: $img，先运行 compile" && return 1
    echo -e "${BLUE}启动 QEMU: $QEMU -drive file=$img,format=raw${NC}"
    echo -e "${YELLOW}[注意] 需要本地图形环境，SSH 远程请用 vnc 命令${NC}"
    $QEMU -drive file="$img",format=raw -serial null -parallel stdio
}

do_run_snake() {
    local img="$SRC_DIR/snake.img"
    [ ! -f "$img" ] && [ -f "$SRC_DIR/snake_game.img" ] && img="$SRC_DIR/snake_game.img"
    [ ! -f "$img" ] && echo "snake 镜像不存在，请先在 $SRC_DIR 运行 compile-all 或 make" && return 1
    echo -e "${BLUE}启动贪吃蛇: $QEMU -drive file=$img,format=raw,if=floppy${NC}"
    echo -e "${YELLOW}[注意] 需要本地图形环境，SSH 远程请用 vnc-snake 命令${NC}"
    $QEMU -drive file="$img",format=raw,if=floppy
}

# ---- VGA 显存验证 (headless, 无需图形界面) ----
do_vga() {
    local name=$1
    local img="$SRC_DIR/${name}.img"
    [ ! -f "$img" ] && echo "镜像不存在: $img" && return 1

    pkill -9 -f qemu-system 2>/dev/null
    sleep 1
    local sock="/tmp/qemu-vga-$$.sock"

    echo -e "${BLUE}--- VGA 验证: $name ---${NC}"
    $QEMU -drive file="$img",format=raw -display none -serial null \
        -monitor unix:$sock,server,nowait -daemonize 2>/dev/null
    sleep 4

    python3 - "$sock" "$name" << 'PYEOF'
import socket, time, sys
sock_path, name = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sock_path)
time.sleep(0.3)
s.recv(4096)

addrs = {
    'a1_helloworld': ['0xb8000'],
    'a1_studentid':  ['0xb8a14'],
    'a1_loop':       ['0xb8a14'],
    'a2_cursor':     ['0xb8000', '0xb8050'],
    'a2_int10h':     ['0xb8a14'],
    'a2_keyboard':   ['0xb8000'],
    'a4_spiral':     ['0xb8000', '0xb8050', '0xb80a0'],
    'mbr_snake':     ['0xb8000'],
}
dump_list = addrs.get(name, ['0xb8000'])

for addr in dump_list:
    s.sendall(f'xp /16hx {addr}\r\n'.encode())
    time.sleep(0.5)
    data = s.recv(4096).decode(errors='replace')
    for line in data.strip().split('\n'):
        if ':' in line and '0x' in line.split(':')[1]:
            vals = line.split(':')[1].strip().split()
            chars = ''
            attr = 0
            for v in vals:
                try:
                    n = int(v, 16)
                    ch = n & 0xFF
                    attr = (n >> 8) & 0xFF
                    if 0x20 <= ch < 0x7F:
                        chars += chr(ch)
                except:
                    pass
            print(f'  {line.strip()}')
            if chars.strip():
                print(f'    => Text: "{chars}"  (attr: 0x{attr:02X})')

s.sendall(b'quit\r\n')
time.sleep(0.3)
s.close()
PYEOF

    pkill -9 -f qemu-system 2>/dev/null
    echo ""
}

do_vga_all() {
    for name in a1_helloworld a1_studentid a1_loop a2_cursor a2_int10h a4_spiral; do
        [ -f "$SRC_DIR/${name}.img" ] && do_vga "$name"
    done
}

# ---- GDB 调试 (使用 x86_64-elf-gdb 匹配 qemu-system-x86_64) ----
do_gdb_start() {
    local name=$1
    local img="$SRC_DIR/${name}.img"
    [ ! -f "$img" ] && echo "镜像不存在" && return 1
    pkill -9 -f qemu-system 2>/dev/null
    sleep 1
    echo -e "${BLUE}启动 QEMU 等待 GDB (端口 1234)...${NC}"
    echo "  $QEMU -drive file=$img,format=raw -s -S -display none -serial null"
    $QEMU -drive file="$img",format=raw -s -S -display none -serial null &
    sleep 1
    echo ""
    echo -e "${GREEN}QEMU 已启动，请在另一终端执行:${NC}"
    echo "  $GDB_X64"
    echo "  (gdb) target remote :1234"
    if [ -f "$SRC_DIR/${name}.symbol" ]; then
        echo "  (gdb) add-symbol-file $SRC_DIR/${name}.symbol 0x7c00"
    fi
    echo "  (gdb) b *0x7c00"
    echo "  (gdb) c"
    echo '  (gdb) x/10i $pc'
    echo "  (gdb) info registers"
    echo "  (gdb) si"
}

do_gdb_connect() {
    echo -e "${BLUE}连接 GDB...${NC}"
    $GDB_X64 \
        -ex 'target remote :1234' \
        -ex 'b *0x7c00' \
        -ex 'c'
}

do_gdb_auto() {
    local name=$1
    local img="$SRC_DIR/${name}.img"
    [ ! -f "$img" ] && echo "镜像不存在" && return 1

    pkill -9 -f qemu-system 2>/dev/null
    sleep 1

    echo -e "${BLUE}--- GDB 自动调试演示: $name ---${NC}"
    $QEMU -drive file="$img",format=raw -s -S -display none -serial null &
    local QPID=$!
    sleep 2

    $GDB_X64 -batch \
        -ex 'target remote :1234' \
        -ex "add-symbol-file $SRC_DIR/${name}.symbol 0x7c00" \
        -ex 'b *0x7c00' \
        -ex 'c' \
        -ex 'x/10i $pc' \
        -ex 'info registers rax rbx rcx rdx rsi rdi rsp rbp rip eflags cs ds ss es gs' \
        -ex 'si' \
        -ex 'si' \
        -ex 'si' \
        -ex 'x/5i $pc' \
        -ex 'disconnect' \
        -ex 'quit' 2>&1

    kill $QPID 2>/dev/null
    wait $QPID 2>/dev/null
    echo ""
}

# ---- Assignment 3 ----
do_a3_compile() {
    echo -e "${BLUE}--- Assignment 3: 编译 student.asm (ELF32) ---${NC}"
    cd "$ASG_DIR"
    echo "  nasm -f elf32 student.asm -o student.o"
    nasm -f elf32 student.asm -o student.o 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[OK]${NC} student.o 编译成功"
        file student.o
    else
        echo -e "${YELLOW}[FAIL]${NC} 编译失败"
    fi
    echo ""
    echo "注意: ARM64 上无法 g++ -m32，完整测试需在 x86_64 环境执行 make run"
}

# ---- 查看源码 ----
do_show() {
    local name=$1
    local asm="$SRC_DIR/${name}.asm"
    [ ! -f "$asm" ] && asm="$ASG_DIR/${name}.asm"
    [ ! -f "$asm" ] && echo "文件不存在" && return 1
    echo -e "${CYAN}=== $asm ===${NC}"
    cat -n "$asm"
}

do_list() {
    echo -e "${CYAN}=== 源码文件 (.asm) ===${NC}"
    ls -lh $SRC_DIR/*.asm $ASG_DIR/*.asm 2>/dev/null
    echo ""
    echo -e "${CYAN}=== 编译产物 (.bin .img .symbol) ===${NC}"
    ls -lh $SRC_DIR/*.bin $SRC_DIR/*.img $SRC_DIR/*.symbol 2>/dev/null
    echo ""
    echo -e "${CYAN}=== 验证日志 ===${NC}"
    ls -lh $LAB2_DIR/results/ 2>/dev/null
}

# ---- 主入口 ----
case "${1:-help}" in
    compile)      do_compile "$2" ;;
    compile-all)  do_compile_all ;;
    vnc)          do_vnc "$2" ;;
    vnc-snake)    do_vnc_snake ;;
    vnc-stop)     do_vnc_stop ;;
    remote-vnc)   do_remote_view "vnc" "$2" ;;
    remote-vnc-snake) do_remote_view "vnc" "snake" ;;
    spice)        do_spice "$2" ;;
    spice-snake)  do_spice_snake ;;
    spice-stop)   do_spice_stop ;;
    remote-spice) do_remote_view "spice" "$2" ;;
    remote-spice-snake) do_remote_view "spice" "snake" ;;
    remote-stop)  do_remote_stop ;;
    run)          do_run "$2" ;;
    run-snake)    do_run_snake ;;
    vga)          do_vga "$2" ;;
    vga-all)      do_vga_all ;;
    gdb-start)    do_gdb_start "$2" ;;
    gdb-connect)  do_gdb_connect ;;
    gdb-auto)     do_gdb_auto "$2" ;;
    a3-compile)   do_a3_compile ;;
    show)         do_show "$2" ;;
    list)         do_list ;;
    help|*)       show_help ;;
esac
