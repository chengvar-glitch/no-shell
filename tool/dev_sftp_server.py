"""一次性本地 SFTP 服务端：仅绑定 127.0.0.1，密码 smoke / 密钥均可登录。

用法：/tmp/sftp-venv/bin/python tool/dev_sftp_server.py <根目录> [端口]
用于真实链路冒烟：dart run tool/smoke_ssh.dart 127.0.0.1 <端口> smoke --password smoke --sftp
"""

import asyncio
import socket
import sys
from pathlib import Path

import asyncssh


async def main() -> None:
    root = Path(sys.argv[1]).resolve()
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 2222
    root.mkdir(parents=True, exist_ok=True)
    (root / 'hello.txt').write_text('hello from server\n')
    (root / 'logs').mkdir(exist_ok=True)
    (root / 'logs' / 'app.log').write_text('line1\nline2\n')

    class SmokeServer(asyncssh.SSHServer):
        # 只接受 smoke/smoke，避免暴露系统账户。
        def begin_auth(self, username: str) -> bool:
            return username == 'smoke'

        def password_auth_supported(self) -> bool:
            return True

        def validate_password(self, username: str, password: str) -> bool:
            return username == 'smoke' and password == 'smoke'

    async with asyncssh.listen(
        '127.0.0.1',
        port,
        family=socket.AF_INET,
        server_host_keys=[asyncssh.generate_private_key('ssh-ed25519')],
        server_factory=SmokeServer,
        sftp_factory=lambda ch: asyncssh.SFTPServer(ch, chroot=root),
        allow_scp=True,
    ):
        print(f'SFTP server ready on 127.0.0.1:{port} root={root}', flush=True)
        await asyncio.Event().wait()  # 一直运行，外部负责杀进程


if __name__ == '__main__':
    asyncio.run(main())
