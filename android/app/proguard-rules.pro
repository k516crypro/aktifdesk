# AktifDesk release — obfuscate + shrink. Honest limit: slows RE, not perfect.

-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep Accessibility / FGS entry points
-keep class com.aktifdesk.aktifdesk.RemoteAccessibilityService { *; }
-keep class com.aktifdesk.aktifdesk.HostForegroundService { *; }
-keep class com.aktifdesk.aktifdesk.MainActivity { *; }

-keepattributes Signature
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Strip logging in release
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}

# Flutter Play Store deferred components (not used) — ignore missing Play Core
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
