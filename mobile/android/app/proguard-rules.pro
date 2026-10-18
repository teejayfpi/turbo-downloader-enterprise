# Flutter and plugin classes are reached reflectively.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.turbodl.turbo_downloader.** { *; }
-dontwarn io.flutter.embedding.**
# Only referenced by Flutter's Play Store split-install path, which this app
# does not use (no deferred components).
-dontwarn com.google.android.play.core.**

# The embedded yt-dlp engine (youtubedl-android) reaches its classes and the
# native libraries it unpacks by name, so R8 must not rename or strip them.
# The library ships its rules as a normal proguard file rather than a consumer
# one, so they do not apply here on their own.
-keep class com.yausername.** { *; }
-keep class com.fasterxml.jackson.** { *; }
-keep class org.apache.commons.** { *; }
-dontwarn com.fasterxml.jackson.**
-dontwarn org.apache.commons.**
