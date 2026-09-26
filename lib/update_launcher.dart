/// 打开发布页：url_launcher 六端通吃——原生交给系统浏览器，web 用
/// `webOnlyWindowName: '_blank'` 开新标签页（不会把应用自己导航走）。
/// 曾经对 web 挂恒失败的桩，但 url_launcher 在 web 上本来就能用，
/// 「能工作却报打不开」只是白砍一条路径。
library;

export 'update_launcher_io.dart';
