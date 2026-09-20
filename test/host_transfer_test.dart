import 'package:flutter_test/flutter_test.dart';

import 'package:no_shell/host_portable.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/store.dart';

void main() {
  group('文本解析：中英文 key 均可识别', () {
    test('用户示例格式（中文 key）', () {
      final drafts = parseHostsText(
        '名称: fofo\n地址: 192.0.2.10\n端口: 22\n用户: root\n密码: demo-pass-123',
        defaultGroup: '导入',
      );
      expect(drafts, hasLength(1));
      expect(drafts.first.name, 'fofo');
      expect(drafts.first.host, '192.0.2.10');
      expect(drafts.first.port, 22);
      expect(drafts.first.username, 'root');
      expect(drafts.first.password, 'demo-pass-123');
      expect(drafts.first.group, '导入');
    });

    test('英文 key 大小写不敏感', () {
      final drafts = parseHostsText(
        'Name: web\nAddress: 10.0.0.1\nPort: 2222\nUser: deploy\nPASSWORD: p1',
        defaultGroup: 'g',
      );
      expect(drafts, hasLength(1));
      expect(drafts.first.name, 'web');
      expect(drafts.first.host, '10.0.0.1');
      expect(drafts.first.port, 2222);
      expect(drafts.first.username, 'deploy');
      expect(drafts.first.password, 'p1');
    });

    test('全角冒号与多余空白', () {
      final drafts = parseHostsText(
        '名称： web2\n地址： 192.168.1.1 ： ',
        defaultGroup: 'g',
      );
      expect(drafts, hasLength(1));
      expect(drafts.first.name, 'web2');
      // 值中的全角冒号不再切分，整段保留。
      expect(drafts.first.host, '192.168.1.1 ：');
    });

    test('空行分块 + 注释行 + 缺省值', () {
      final drafts = parseHostsText(
        '# 服务器清单\n'
        '地址: 10.0.0.2\n'
        '端口: abc\n'
        '\n'
        'Name: db\nHost: 10.0.0.3\nUser: postgres\n',
        defaultGroup: '默认分组',
      );
      expect(drafts, hasLength(2));
      // 缺名称/用户名回退为地址，端口非法回落 22。
      expect(drafts[0].name, '10.0.0.2');
      expect(drafts[0].username, '10.0.0.2');
      expect(drafts[0].port, 22);
      expect(drafts[0].password, isNull);
      expect(drafts[0].group, '默认分组');
      expect(drafts[1].port, 22);
    });

    test('分组 key 与端口越界', () {
      final drafts = parseHostsText(
        '地址: 10.0.0.4\n分组: 生产环境\n端口: 99999',
        defaultGroup: 'g',
      );
      expect(drafts.single.group, '生产环境');
      expect(drafts.single.port, 22);
    });

    test('没有地址的块被忽略', () {
      final drafts = parseHostsText('名称: 孤块\n端口: 22', defaultGroup: 'g');
      expect(drafts, isEmpty);
    });
  });

  group('导出编码与回环', () {
    test('固定中文 key 导出，无密码不出密码行，可再解析回来', () {
      final text = encodeHostsText([
        (
          server: SshServer(
            id: 'a',
            group: '生产',
            name: 'fofo',
            host: '192.0.2.10',
            username: 'root',
          ),
          password: null,
        ),
        (
          server: SshServer(
            id: 'b',
            group: '',
            name: 'api',
            host: '10.0.1.20',
            port: 2222,
            username: 'ops',
          ),
          password: 'secret',
        ),
      ]);

      expect(text.contains('密码: secret'), isTrue);
      expect(text.contains('密码: null'), isFalse);
      expect(text.contains('分组: 生产'), isTrue);
      // 空分组不输出分组行。
      expect('分组:'.allMatches(text), hasLength(1));

      final drafts = parseHostsText(text, defaultGroup: '导入');
      expect(drafts, hasLength(2));
      expect(drafts[0].host, '192.0.2.10');
      // 分组随导出保留，不落到默认分组。
      expect(drafts[0].group, '生产');
      expect(drafts[0].password, isNull);
      expect(drafts[1].port, 2222);
      expect(drafts[1].password, 'secret');
    });
  });

  group('单台主机复制文本', () {
    SshServer server({String group = '生产'}) => SshServer(
      id: 'a',
      group: group,
      name: 'fofo',
      host: '192.0.2.10',
      port: 2222,
      username: 'root',
    );

    test('五行固定格式：密码行始终在，分组不输出', () {
      expect(
        encodeServerText(server(), password: 'demo-pass-123'),
        '名称: fofo\n'
        '地址: 192.0.2.10\n'
        '端口: 2222\n'
        '用户: root\n'
        '密码: demo-pass-123\n',
      );
    });

    test('没记住密码时留一行空密码，复制的文本照样能解析回来', () {
      final text = encodeServerText(server());

      expect(text.contains('密码: \n'), isTrue);
      expect(text.contains('分组:'), isFalse);
      final drafts = parseHostsText(text, defaultGroup: '导入');
      expect(drafts.single.host, '192.0.2.10');
      expect(drafts.single.port, 2222);
      expect(drafts.single.username, 'root');
      expect(drafts.single.password, isNull);
    });
  });

  group('ServerStore.importServers', () {
    test('新增去重：与列表、与批次内部重复都跳过，无新增不通知', () {
      final store = ServerStore(
        seed: [
          SshServer(
            id: 'a',
            group: 'g',
            name: 'a',
            host: '10.0.0.1',
            username: 'root',
          ),
        ],
      );
      var notifications = 0;
      store.addListener(() => notifications++);

      final added = store.importServers([
        SshServer(
          id: 'b',
          group: 'g',
          name: 'b',
          host: '10.0.0.1',
          username: 'root',
        ),
        SshServer(
          id: 'c',
          group: 'g',
          name: 'c',
          host: '10.0.0.2',
          port: 22,
          username: 'ops',
        ),
        SshServer(
          id: 'd',
          group: 'g',
          name: 'd',
          host: '10.0.0.2',
          port: 22,
          username: 'ops',
        ),
      ]);

      expect(added.map((s) => s.id), ['c']);
      expect(store.serverCount, 2);
      expect(notifications, 1);

      expect(store.importServers(const []), isEmpty);
      expect(notifications, 1);
    });
  });
}
