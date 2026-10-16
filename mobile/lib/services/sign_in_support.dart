import 'dart:io';

/// True when the app can show the embedded YouTube sign-in.
///
/// Only the platforms that ship a web view and where the sandbox hides other
/// apps' cookie stores. Linux has no embedded web view, so sign-in there stays
/// file/browser based. The widget-test harness has no plugin, so tests never
/// take the sign-in route.
bool get supportsInAppYouTubeSignIn {
  if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
  return Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;
}
