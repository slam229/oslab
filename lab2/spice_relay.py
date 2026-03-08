#!/usr/bin/env python3
"""
SPICE TCP Relay - 通过 SSH 管道中继 SPICE 流量
==============================================
原理: 本系统 SSH -L 端口转发不可用，改用 ssh + nc 管道中继方式。
      本地监听 127.0.0.1:5931，通过 ssh nc 转发到远端 SPICE 端口 5930。

用法:
  1. 远端: bash demo_lab2.sh spice <name>
  2. 本端: python3 spice_relay.py
  3. 本端: remote-viewer spice://127.0.0.1:5931
          或 spicy -h 127.0.0.1 -p 5931

依赖: macOS 需安装 SPICE 客户端:
  brew install virt-viewer    (提供 remote-viewer)
"""
import socket
import subprocess
import threading
import signal
import sys
import time

# ---- 配置 ----
SSH_CMD = ['ssh', '-p', '722', 'cpf@127.0.0.1', 'nc', '127.0.0.1', '5930']
LOCAL_HOST = '127.0.0.1'
LOCAL_PORT = 5931
BUFFER_SIZE = 65536

running = True


def relay_client(client_sock, addr):
    """为每个 SPICE 客户端连接建立一条 SSH 管道"""
    global running
    print(f"[+] SPICE 客户端连接: {addr}")

    try:
        proc = subprocess.Popen(
            SSH_CMD,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except Exception as e:
        print(f"[-] SSH 管道创建失败: {e}")
        client_sock.close()
        return

    def client_to_ssh():
        """客户端 -> SSH -> 远端 SPICE"""
        try:
            while running:
                data = client_sock.recv(BUFFER_SIZE)
                if not data:
                    break
                proc.stdin.write(data)
                proc.stdin.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            try:
                proc.stdin.close()
            except:
                pass

    def ssh_to_client():
        """远端 SPICE -> SSH -> 客户端"""
        try:
            while running:
                data = proc.stdout.read(BUFFER_SIZE)
                if not data:
                    break
                client_sock.sendall(data)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            try:
                client_sock.close()
            except:
                pass

    t1 = threading.Thread(target=client_to_ssh, daemon=True)
    t2 = threading.Thread(target=ssh_to_client, daemon=True)
    t1.start()
    t2.start()

    t1.join()
    t2.join()

    proc.terminate()
    proc.wait()
    try:
        client_sock.close()
    except:
        pass
    print(f"[-] SPICE 客户端断开: {addr}")


def main():
    global running

    def signal_handler(sig, frame):
        global running
        running = False
        print("\n[*] 正在关闭 SPICE 中继...")
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # 检查远端 SPICE 端口是否可达
    print("[*] 检查远端 SPICE 端口 (ssh nc 127.0.0.1 5930)...")
    try:
        check = subprocess.run(
            SSH_CMD[:4] + ['ss', '-tlnp', '|', 'grep', '5930'],
            capture_output=True, text=True, timeout=10
        )
        if '5930' not in check.stdout:
            print("[!] 警告: 远端 SPICE 端口 5930 似乎未监听")
            print("    请先在远端运行: bash demo_lab2.sh spice <name>")
            print("    继续尝试启动中继...\n")
    except:
        pass

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.settimeout(1)

    try:
        server.bind((LOCAL_HOST, LOCAL_PORT))
    except OSError as e:
        print(f"[-] 无法绑定 {LOCAL_HOST}:{LOCAL_PORT}: {e}")
        print("    端口可能被占用，请先停止其他 SPICE 中继")
        sys.exit(1)

    server.listen(5)
    print(f"[*] SPICE 中继已启动: {LOCAL_HOST}:{LOCAL_PORT} → 远端 5930")
    print(f"[*] 连接命令:")
    print(f"    remote-viewer spice://127.0.0.1:{LOCAL_PORT}")
    print(f"    或: spicy -h 127.0.0.1 -p {LOCAL_PORT}")
    print(f"[*] Ctrl+C 停止中继\n")

    while running:
        try:
            client_sock, addr = server.accept()
            t = threading.Thread(target=relay_client, args=(client_sock, addr), daemon=True)
            t.start()
        except socket.timeout:
            continue
        except KeyboardInterrupt:
            break

    server.close()
    print("[*] SPICE 中继已关闭")


if __name__ == '__main__':
    main()
