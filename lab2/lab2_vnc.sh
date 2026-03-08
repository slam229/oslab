#!/bin/bash
# ============================================================================
# Lab2 VNC 本地一键脚本 (在 Mac 上运行，用于观察麒麟虚拟机中的 QEMU)
# 用法:
#   bash lab2_vnc.sh <name>           一键启动 VNC 查看
#               一键启动贪吃蛇
#   bash lab2_vnc.sh stop             停止 QEMU 和中继
#   bash lab2_vnc.sh relay [port]     仅启动 VNC 中继 (QEMU 已在运行)
#
# 原理:
#   1. SSH 到远端麒麟虚拟机启动 QEMU (带 VNC 服务端)
#   2. 本地启动 Python VNC 中继 (通过 SSH 管道转发 VNC 流量，自动跟随远端端口)
#   3. macOS "屏幕共享" 连接本地中继端口查看 QEMU 画面
# ============================================================================

SSH_CMD="ssh -p 722 cpf@127.0.0.1"
REMOTE_SCRIPT="/home/cpf/OSLab-i386-2026/lab2/demo_lab2.sh"
LOCAL_RELAY_PORT=5901
REMOTE_VNC_PORT=5900
VNC_PASSWORD="1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# 停止所有相关进程
do_stop() {
    echo -e "${BLUE}停止中继和远端 QEMU...${NC}"
    pkill -f "vnc_relay_inner" 2>/dev/null
    pkill -f "python3.*vnc_relay" 2>/dev/null
    $SSH_CMD "pkill -9 qemu 2>/dev/null" 2>/dev/null
    echo -e "${GREEN}[OK] 已停止${NC}"
}

# 启动 VNC 中继 (内嵌 Python，无需额外文件)
start_relay() {
    local remote_port=${1:-$REMOTE_VNC_PORT}
    # 先杀旧中继
    pkill -f "vnc_relay_inner" 2>/dev/null
    sleep 1

    python3 -c "
# vnc_relay_inner
import subprocess, socket, threading, sys, os, signal

LOCAL_PORT = $LOCAL_RELAY_PORT
SSH_CMD = ['ssh', '-p', '722', 'cpf@127.0.0.1', 'nc', '127.0.0.1', '$remote_port']

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
    except:
        pass

def handle(client, addr):
    print(f'[+] VNC client: {addr}', flush=True)
    proc = subprocess.Popen(SSH_CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    t1 = threading.Thread(target=relay, args=(client, proc.stdin), daemon=True)
    t2 = threading.Thread(target=relay, args=(proc.stdout, client), daemon=True)
    t1.start(); t2.start()
    t1.join(); t2.join()
    proc.terminate(); client.close()
    print(f'[-] VNC disconnected: {addr}', flush=True)

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('127.0.0.1', LOCAL_PORT))
server.listen(5)
print(f'VNC relay listening on 127.0.0.1:{LOCAL_PORT}', flush=True)
signal.signal(signal.SIGINT, lambda *a: (server.close(), sys.exit(0)))
while True:
    try:
        c, a = server.accept()
        threading.Thread(target=handle, args=(c, a), daemon=True).start()
    except OSError:
        break
" &

    RELAY_PID=$!
    sleep 2

    # 检查中继是否成功启动
    if kill -0 $RELAY_PID 2>/dev/null; then
        echo -e "${GREEN}[OK] VNC 中继已启动 (PID: $RELAY_PID, 本地端口: $LOCAL_RELAY_PORT, 远端端口: $remote_port)${NC}"
        return 0
    else
        echo -e "${RED}[ERROR] VNC 中继启动失败${NC}"
        return 1
    fi
}

# 一键启动: SSH 启动远端 QEMU + 本地中继 + 打开 VNC
do_vnc() {
    local name=$1
    local remote_port=$REMOTE_VNC_PORT

    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}  Lab2 VNC 远程查看: $name${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""

    # Step 1: 远端启动 QEMU + VNC
    echo -e "${BLUE}[1/3] 远端启动 QEMU + VNC ...${NC}"
    local ssh_output
    if [ "$name" = "snake" ]; then
        ssh_output=$($SSH_CMD "pkill -9 qemu 2>/dev/null; sleep 1; bash $REMOTE_SCRIPT vnc-snake" 2>&1)
    else
        ssh_output=$($SSH_CMD "pkill -9 qemu 2>/dev/null; sleep 1; bash $REMOTE_SCRIPT vnc $name" 2>&1)
    fi
    local ssh_rc=$?

    echo "$ssh_output" | grep -v '^Authorized\|^$'

    if echo "$ssh_output" | grep -q 'VNC 监听端口'; then
        remote_port=$(echo "$ssh_output" | sed -n 's/.*VNC 监听端口 \([0-9][0-9]*\).*/\1/p' | tail -n 1)
    fi

    if [ $ssh_rc -ne 0 ]; then
        echo -e "${RED}[ERROR] 远端 QEMU 启动失败 (SSH exit code: $ssh_rc)${NC}"
        echo -e "${RED}$ssh_output${NC}"
        return 1
    fi

    # 再确认远端 QEMU 是否真的在运行
    if ! $SSH_CMD "pgrep -x qemu-system-x86" >/dev/null 2>&1; then
        # 也可能进程名被截断，换个方式
        if ! $SSH_CMD "pgrep -f qemu-system-x86_64" >/dev/null 2>&1; then
            echo -e "${RED}[ERROR] 远端 QEMU 进程未找到${NC}"
            return 1
        fi
    fi

    # Step 2: 启动本地 VNC 中继
    echo -e "${BLUE}[2/3] 启动本地 VNC 中继 ...${NC}"
    start_relay "$remote_port"
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Step 3: 打开 macOS VNC 客户端
    echo -e "${BLUE}[3/3] 打开 macOS VNC 客户端 ...${NC}"
    echo -e "${YELLOW}  VNC 密码: $VNC_PASSWORD${NC}"
    echo ""
    open "vnc://127.0.0.1:$LOCAL_RELAY_PORT"

    echo -e "${GREEN}=== VNC 已启动 ===${NC}"
    echo -e "  切换程序: bash lab2_vnc.sh <其他name>"
    echo -e "  停止:     bash lab2_vnc.sh stop"
    echo ""
    echo -e "  ${YELLOW}可用的 name:${NC}"
    echo "    a1_helloworld  a1_studentid  a1_loop"
    echo "    a2_cursor      a2_int10h     a2_keyboard"
    echo "    a4_spiral      mbr_snake     snake"
}

# ---- 主入口 ----
case "${1:-help}" in
    stop)
        do_stop ;;
    relay)
        start_relay "$2" ;;
    help|-h|--help)
        echo "用法: bash lab2_vnc.sh <name|snake|stop|relay [port]>"
        echo ""
        echo "  <name>   在麒麟虚拟机中启动指定程序，并在 Mac 上打开 VNC 查看"
        echo "  snake    在麒麟虚拟机中启动贪吃蛇，并在 Mac 上打开 VNC 查看"
        echo "  stop     停止远端 QEMU 和本地中继"
        echo "  relay    仅启动本地 VNC 中继，可选指定远端端口"
        echo ""
        echo "说明:"
        echo "  - 这是 Mac 端入口脚本；虚拟机内实际运行的是 demo_lab2.sh"
        echo "  - 若当前机器有图形界面，也可直接在虚拟机内运行: bash demo_lab2.sh run-snake"
        echo ""
        echo "可用的 name:"
        echo "  a1_helloworld  a1_studentid  a1_loop"
        echo "  a2_cursor      a2_int10h     a2_keyboard"
        echo "  a4_spiral      mbr_snake     snake"
        ;;
    *)
        do_vnc "$1" ;;
esac
