# App-specific R8 rules. Picked up by the Flutter Gradle plugin automatically
# for release builds: it adds `proguard-rules.pro` from this directory when the
# file exists.

# ML Kit starts up by reading its component registrars' class names out of the
# manifest and constructing each one reflectively, through its no-argument
# constructor.
#
# The rule the Firebase components library ships for them is
# `-keep class * implements com.google.firebase.components.ComponentRegistrar`,
# which names the classes but not their members. R8's full mode — the default
# since AGP 8 — keeps nothing a rule does not name, so the constructors were
# removed and every registrar failed with `NoSuchMethodException: <init>`:
# ML Kit came up with no components at all. On a release build that made
# `Translation.getClient` throw a NullPointerException before a language pack
# was ever asked for, and made screen reading quietly return nothing. A debug
# build is not shrunk, which is why it never showed there.
#
# Found on the Motorola edge 50 fusion (Android 16) as "translation fails".
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    <init>();
}
