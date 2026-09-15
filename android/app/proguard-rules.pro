-keep class net.sqlcipher.** { *; }
-keep class org.webrtc.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# UnifiedPush
-keep class org.unifiedpush.** { *; }

# Matrix SDK
-keep class org.matrix.** { *; }