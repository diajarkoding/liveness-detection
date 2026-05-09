# ===========================================
# Liveness Detection - ProGuard Rules
# ===========================================

# --- Flutter ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# --- ML Kit Face Detection ---
-keep class com.google.mlkit.vision.face.** { *; }
-keep class com.google.android.gms.internal.** { *; }
-dontwarn com.google.mlkit.**

# --- MediaPipe ---
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.mediapipe.**

# --- CameraX ---
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

# --- Kotlin Coroutines ---
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembers class kotlinx.coroutines.** {
    volatile **;
}

# --- App Native Code ---
-keep class com.diajarkoding.livenessdetection.** { *; }
-keepclassmembers class com.diajarkoding.livenessdetection.** { *; }

# --- Sealed Classes (State management) ---
-keep class * extends java.lang.Enum {
    <fields>;
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# --- Anti-tampering ---
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}

# --- General ---
-keepattributes SourceFile,LineNumberTable,Signature,Exceptions,InnerClasses,EnclosingMethod
-renamesourcefileattribute SourceFile
