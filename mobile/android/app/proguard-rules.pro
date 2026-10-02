# Flutter and plugin classes are reached reflectively.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.turbodl.turbo_downloader.** { *; }
-dontwarn io.flutter.embedding.**
# Only referenced by Flutter's Play Store split-install path, which this app
# does not use (no deferred components).
-dontwarn com.google.android.play.core.**
