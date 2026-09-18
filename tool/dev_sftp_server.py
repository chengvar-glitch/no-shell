"""一次性本地 SFTP + 假 shell 服务端：仅绑定 127.0.0.1，密码 smoke / 密钥均可登录。

用法：/tmp/sftp-venv/bin/python tool/dev_sftp_server.py <根目录> [端口]
用于真实链路冒烟：dart run tool/smoke_ssh.dart 127.0.0.1 <端口> smoke --password smoke --sftp
（追加 --shell 验证 PTY）。假 shell 只认识 clear / ls -la / echo / exit，输出固定，
供冒烟与 README 截图得到确定的画面。

注意：asyncssh 在设置了 sftp_factory 时会绕过 SSHServer.session_requested，
所以交互 shell 必须走 process_factory，两者可并存（见 connection.py 的会话分发）。
"""

import asyncio
import logging
import os
import socket
import sys
from pathlib import Path

import asyncssh

# 协议级排障开关：环境变量 SSH_DEBUG=1 时输出 asyncssh DEBUG 日志。
if os.environ.get('SSH_DEBUG') == '1':
    logging.basicConfig(level=logging.DEBUG)
    logging.getLogger('asyncssh').setLevel(logging.DEBUG)

PROMPT = 'demo@localhost:~$ '

# 固定文本，保证截图可复现；与根目录实际内容保持一致。
LS_OUTPUT = (
    'total 16\r\n'
    'drwxr-xr-x 5 demo demo 4096 Sep 16 10:00 .\r\n'
    'drwxr-xr-x 3 demo demo 4096 Sep 16 10:00 ..\r\n'
    '-rw-r--r-- 1 demo demo   27 Sep 16 10:00 hello.txt\r\n'
    'drwxr-xr-x 2 demo demo 4096 Sep 16 10:00 logs\r\n'
    'drwxr-xr-x 2 demo demo 4096 Sep 16 10:00 projects\r\n'
)


def _respond(cmd: str) -> str:
    if cmd == 'clear':
        return '\x1b[2J\x1b[H' + PROMPT
    if cmd.startswith('ls'):
        return '\r\n' + LS_OUTPUT + PROMPT
    if cmd == 'exit':
        return 'bye\r\n'
    return f'\r\nNoShell demo shell: {cmd or "(empty)"}\r\n' + PROMPT


async def demo_shell(process: asyncssh.SSHServerProcess) -> None:
    """交互式假 shell：回显输入，识别 clear / ls -la / echo / exit。"""
    process.stdout.write(PROMPT)
    line = ''
    while True:
        try:
            data = await process.stdin.read(256)
        except asyncssh.TerminalSizeChanged:
            # 视窗变化以异常形式投递给挂起的 read，吞掉后继续收输入；
            # 否则客户端首帧布局触发 window-change 就会把连接整个带崩。
            continue
        if not data:
            return
        # 不做服务端回显：客户端终端已有本地回显，回显会重复一遍。
        line += data
        while '\r' in line or '\n' in line:
            ends = [x for x in (line.find('\r'), line.find('\n')) if x >= 0]
            i = min(ends)
            raw, line = line[:i], line[i + 1:]
            cmd = raw.strip()
            print(f'[shell] cmd={cmd!r}', flush=True)
            response = _respond(cmd)
            process.stdout.write(response)
            if cmd == 'exit':
                process.close()
                return


async def main() -> None:
    root = Path(sys.argv[1]).resolve()
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 2222
    root.mkdir(parents=True, exist_ok=True)
    (root / 'hello.txt').write_text('hello from server\n')
    (root / 'logs').mkdir(exist_ok=True)
    (root / 'logs' / 'app.log').write_text('line1\nline2\n')
    (root / 'projects').mkdir(exist_ok=True)

    class SmokeServer(asyncssh.SSHServer):
        # 只接受 smoke/smoke，避免暴露系统账户。
        def begin_auth(self, username: str) -> bool:
            return username == 'smoke'

        def password_auth_supported(self) -> bool:
            return True

        def validate_password(self, username: str, password: str) -> bool:
            return username == 'smoke' and password == 'smoke'

        def connection_requested(
            self, dest_host, dest_port, orig_host, orig_port
        ):
            # 转发冒烟（test/forward_smoke_test.dart）要把本机当目标，因此要放行
            # direct-tcpip；asyncssh 默认一律拒绝。只放行回环目标：这个一次性
            # 服务端不该同时是一个「可以当任意跳板」的口子。
            if dest_host in ('127.0.0.1', '::1', 'localhost'):
                return True
            return False

    async with asyncssh.listen(
        '127.0.0.1',
        port,
        family=socket.AF_INET,
        server_host_keys=[asyncssh.generate_private_key('ssh-ed25519')],
        server_factory=SmokeServer,
        process_factory=demo_shell,
        sftp_factory=lambda ch: asyncssh.SFTPServer(ch, chroot=root),
        allow_scp=True,
    ):
        print(f'SFTP+shell server ready on 127.0.0.1:{port} root={root}',
              flush=True)
        await asyncio.Event().wait()  # 一直运行，外部负责杀进程


if __name__ == '__main__':
    asyncio.run(main())
