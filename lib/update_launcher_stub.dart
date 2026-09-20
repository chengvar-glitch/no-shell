/// web 桩实现：浏览器里不该把 SSH 应用自己导航走，而发布页又是外站，
/// 这里没有能用的系统浏览器通道，如实返回「打不开」。
Future<bool> openExternalUrl(Uri uri) async => false;
