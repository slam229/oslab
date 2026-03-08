#!/bin/bash
# ============================================================================
# Lab2 一键 SPICE 查看脚本 (Mac 本地运行)
# 用法: bash lab2_spice.sh <name>
# 示例: bash lab2_spice.sh a1_helloworld
#       bash lab2_spice.sh snake
# ============================================================================

SSH_HOST="cpf@127.0.0.1"
SSH_PORT=722
SSH_CMD="ssh -p $SSH_PORT $SSH_HOST"
REMOTE_SCRIPT="/home/cpf/OSLab-i386-2026/lab2/demo_lab2.sh"
SPICE_REMOTE_PORT=5930
SPICE_LOCAL_PORT=5931
RELAY_PID=""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

cleanup() {
    echo ""
    echo -e "${CYAN}[*] 正在清理...${NC}"
    # 停止 SPICE 中继
    [ -n "$RELAY_PID" ] && kill $RELAY_PID 2>/dev/null && echo "  已停止 SPICE 中继 (PID $RELAY_PID)"
    # 停止远端 QEMU
    $SSH_CMD "pkill -9 qemu-system" 2>/dev/null && echo "  已停止远端 QEMU"
    # 清理临时文件
    rm -f /tmp/spice_relay_lab2.py
    echo -e "${GREEN}[OK] 清理完成${NC}"
}
trap cleanup EXIT

# 检查参数
if [ -z "$1" ]; then
    echo -e "${CYAN}用法: bash lab2_spice.sh <name>${NC}"
    echo ""
    echo "可用的 <name>:"
    echo "  a1_helloworld  a1_studentid  a1_loop"
    echo "  a2_cursor      a2_int10h     a2_keyboard"
    echo "  a4_spiral      snake"
    exit 0
fi

name="$1"

# 检查 SPICE 客户端
SPICE_CLIENT=""
if command -v remote-viewer &>/dev/null; then
    SPICE_CLIENT="remote-viewer"
elif command -v spicy &>/dev/null; then
    SPICE_CLIENT="spicy"
fi

if [ -z "$SPICE_CLIENT" ]; then
    echo -e "${YELLOW}[!] 未找到 SPICE 客户端${NC}"
    echo ""
    echo "请安装 virt-viewer (提供 remote-viewer 命令):"
    echo "  brew install virt-viewer"
    echo ""
    echo "或安装 spice-gtk (提供 spicy 命令):"
    echo "  brew install spice-gtk"
    echo ""
    read -p "是否继续启动中继 (手动连接)? [y/N]: " choice
    [ "$choice" != "y" ] && [ "$choice" != "Y" ] && exit 0
fi

# Step 1: 远端启动 QEMU + SPICE
echo -e "${CYAN}=== Step 1: 启动远端 QEMU + SPICE ===${NC}"
if [ "$name" = "snake" ]; then
    REMOTE_CMD="bash $REMOTE_SCRIPT spice-snake"
else
    REMOTE_CMD="bash $REMOTE_SCRIPT spice $name"
fi

output=$($SSH_CMD "$REMOTE_CMD" 2>&1)
echo "$output"

if echo "$output" | grep -q "\[ERROR\]"; then
    echo -e "${RED}[ERROR] 远端 QEMU 启动失败${NC}"
    exit 1
fi

# 等远端 SPICE 就绪
sleep 1

# Step 2: 启动 SPICE 中继 (SSH pipe relay)
echo ""
echo -e "${CYAN}=== Step 2: 启动 SPICE 中继 (端口 $SPICE_LOCAL_PORT) ===${NC}"

# 生成临时 relay 脚本
cat > /tmp/spice_relay_lab2.py << 'RELAYEOF'
import socket, subprocess, threading, signal, sys

SSH_CMD = ['ssh', '-p', '722', 'cpf@127.0.0.1', 'nc', '127.0.0.1', '5930']
LOCAL_HOST, LOCAL_PORT, BUF = '127.0.0.1', 5931, 65536
running = True

def relay(csock, addr):
    proc = subprocess.Popen(SSH_CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    def c2s():
        try:
            while running:
                d = csock.recv(BUF)
                if not d: break
                proc.stdin.write(d); proc.stdin.flush()
        except: pass
        finally:
            try: proc.stdin.close()
            except: pass
    def s2c():
        try:
            while running:
                d = proc.stdout.read(BUF)
                if not d: break
                csock.sendall(d)
        except: pass
        finally:
            try: csock.close()
            except: pass
    t1 = threading.Thread(target=c2s, daemon=True); t1.start()
    t2 = threading.Thread(target=s2c, daemon=True); t2.start()
    t1.join(); t2.join()
    proc.terminate(); proc.wait()
    try: csock.close()
    except: pass

def main():
    global running
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.settimeout(1)
    srv.bind((LOCAL_HOST, LOCAL_PORT)); srv.listen(5)
    while running:
        try:
            cs, addr = srv.accept()
            threading.Thread(target=relay, args=(cs, addr), daemon=True).start()
        except socket.timeout: continue
        except: break
    srv.close()

if __name__ == '__main__': main()
RELAYEOF

python3 /tmp/spice_relay_lab2.py &
RELAY_PID=$!
sleep 1

# 检查中继是否正常
if ! kill -0 $RELAY_PID 2>/dev/null; then
    echo -e "${RED}[ERROR] SPICE 中继启动失败 (端口可能被占用)${NC}"
    exit 1
fi
echo -e "${GREEN}[OK] SPICE 中继已启动 (PID $RELAY_PID)${NC}"

# Step 3: 打开 SPICE 客户端
echo ""
echo -e "${CYAN}=== Step 3: 连接 SPICE ===${NC}"
sleep 1

if [ "$SPICE_CLIENT" = "remote-viewer" ]; then
    echo -e "${GREEN}[*] 正在打开 remote-viewer...${NC}"
    remote-viewer "spice://127.0.0.1:$SPICE_LOCAL_PORT" 2>/dev/null
elif [ "$SPICE_CLIENT" = "spicy" ]; then
    echo -e "${GREEN}[*] 正在打开 spicy...${NC}"
    spicy -h 127.0.0.1 -p $SPICE_LOCAL_PORT 2>/dev/null
else
    echo -e "${YELLOW}[*] SPICE 中继已就绪，请手动连接:${NC}"
    echo -e "    remote-viewer spice://127.0.0.1:$SPICE_LOCAL_PORT"
    echo -e "    或: spicy -h 127.0.0.1 -p $SPICE_LOCAL_PORT"
    echo ""
    echo "按 Enter 或 Ctrl+C 结束..."
    read
fi

echo ""
echo -e "${GREEN}[OK] SPICE 会话结束${NC}"
