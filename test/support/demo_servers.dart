import 'package:no_shell/models.dart';

/// 桌面 / 移动端组件测试共用的示例主机列表（应用出厂已不再预置数据，
/// 需要非空列表语义的测试经 `ServerStore(seed: demoServers)` 显式注入）。
final List<SshServer> demoServers = [
  SshServer(
    id: 'srv-01',
    group: '生产环境',
    name: 'web-prod-01',
    host: '10.0.1.11',
    username: 'deploy',
    tags: const ['nginx', 'web'],
    lastConnectedAt: DateTime.now().subtract(const Duration(minutes: 26)),
    notes: '主站前端负载节点，变更需走审批流程。',
  ),
  const SshServer(
    id: 'srv-02',
    group: '生产环境',
    name: 'web-prod-02',
    host: '10.0.1.12',
    username: 'deploy',
    tags: ['nginx', 'web'],
  ),
  const SshServer(
    id: 'srv-03',
    group: '生产环境',
    name: 'api-gateway',
    host: '10.0.1.20',
    port: 2222,
    username: 'ops',
    authMethod: AuthMethod.password,
    tags: ['gateway', 'api'],
  ),
  const SshServer(
    id: 'srv-04',
    group: '开发 / 测试',
    name: 'db-primary',
    host: '10.0.2.31',
    username: 'root',
    tags: ['postgres'],
  ),
  const SshServer(
    id: 'srv-05',
    group: '开发 / 测试',
    name: 'redis-cache',
    host: '10.0.2.32',
    username: 'root',
  ),
  const SshServer(
    id: 'srv-06',
    group: '开发 / 测试',
    name: 'ci-runner',
    host: '10.0.2.40',
    username: 'ci',
    tags: ['jenkins'],
  ),
  const SshServer(
    id: 'srv-07',
    group: '个人服务器',
    name: 'nas-home',
    host: '192.168.1.10',
    username: 'admin',
    tags: ['nas', 'home'],
  ),
  const SshServer(
    id: 'srv-08',
    group: '个人服务器',
    name: 'vps-blog',
    host: '47.98.12.34',
    username: 'ubuntu',
    tags: ['blog'],
  ),
];
