// Stub for dart:io Platform and Process on web
class Platform {
  static bool get isWindows => false;
  static bool get isMacOS => false;
  static bool get isLinux => false;
  static bool get isAndroid => false;
  static bool get isIOS => false;
}

class Process {
  static Future<dynamic> run(String executable, List<String> arguments) async {
    // No-op on web
    return null;
  }
}
