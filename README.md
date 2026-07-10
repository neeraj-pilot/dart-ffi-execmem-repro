# Dart FFI executable-memory reproduction

Minimal Flutter/Android reproductions for a Dart FFI callback crash when the
operating system rejects a writable-to-executable memory transition.

The field report that prompted this investigation came from Ente Auth on
GrapheneOS with **Dynamic code loading via memory** restricted:

```text
virtual_memory_posix.cc: ...: error: mprotect failed: 13 (Permission denied)
signal 6 (SIGABRT)
```

The default project is deliberately free of Cronet and JNI dependencies. A
separate nested project demonstrates the same failure through
`cronet_http` 1.9.0 without changing the minimal APK.

Read the engineer-facing explanation at
[neeraj-pilot.github.io/dart-ffi-execmem-repro](https://neeraj-pilot.github.io/dart-ffi-execmem-repro/).

## What this demonstrates

A Flutter release build is ahead-of-time compiled, but native-to-Dart FFI
callbacks still need a native function pointer. On Android, the Dart VM copies
a callback trampoline into runtime-allocated memory and changes that memory to
read/execute. If the `mprotect(..., PROT_EXEC)` request returns `EACCES`, the VM
aborts.

This is not a claim that:

- Flutter release builds use a general-purpose JIT;
- all Flutter plugins or Dart FFI calls need executable memory;
- the test filter implements the complete GrapheneOS policy; or
- Chromium's Cronet engine itself creates the Dart trampoline.

## Tested environment

- Flutter 3.38.10, framework revision `c6f67dede3d4aa1aa7a69dd56a3494a5cde6cc80`
- Flutter engine revision `cafcda5721a78a7884db92f13c5e89f7643d52dd`
- ARM64 `libflutter.so` ELF Build ID `f3f508e0190eca0d72f06dcf36164aa63001ff01`
- Dart 3.10.9
- Android ARM64 API 34 emulator
- Release/AOT builds
- `cronet_http` 1.9.0 for the isolated Cronet scenario

Results verified on 10 July 2026:

| Executable-memory policy | Trigger | Result |
| --- | --- | --- |
| Allowed | `Pointer.fromFunction` | App starts and displays `42` |
| Targeted denial | No callback | App remains running |
| Targeted denial | `Pointer.fromFunction` | `mprotect/EACCES`, then SIGABRT |
| Targeted denial | `NativeCallable.isolateLocal` | `mprotect/EACCES`, then SIGABRT |
| Allowed | Cronet 1.9.0 loopback request | HTTP 204 |
| Targeted denial | Cronet 1.9.0 loopback request | `mprotect/EACCES`, then SIGABRT |

The targeted denial is a six-instruction seccomp filter that returns `EACCES`
only for ARM64 `mprotect` calls containing `PROT_EXEC`. It reproduces the
kernel-visible failure from the GrapheneOS report; it does not reproduce the
rest of GrapheneOS.

## Project layout

```text
lib/main.dart             Minimal Pointer.fromFunction reproduction
lib/control_main.dart     Equivalent Flutter UI without an FFI callback
lib/harness_main.dart     Controlled none/pointer/native matrix
lib/execmem_filter.dart   Android ARM64 test filter
cronet_repro/             Isolated Cronet 1.9.0 loopback scenario
site/                     GitHub Pages article
```

## Requirements

- Flutter 3.38.10, or a Flutter release bundling Dart 3.10.9 or later
  within the 3.x SDK range
- Android SDK and `adb`
- An ARM64 Android device or emulator
- Release mode; debug/profile modes are not valid controls because they have
  separate runtime-code requirements

The generated release APKs are debug-signed for local installation. They are
not distribution artifacts.

## Minimal GrapheneOS reproduction

Build the no-callback control first:

```sh
flutter pub get
flutter build apk --release --target-platform android-arm64 \
  --target lib/control_main.dart
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

In GrapheneOS, set **Settings → Apps → Dart FFI execmem repro → Exploit
protection → Dynamic code loading via memory → Restricted**, force-stop the
app, and launch it. The control should display `No callback: app is running`.

Then build and install the callback target:

```sh
flutter build apk --release --target-platform android-arm64 \
  --target lib/main.dart
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am force-stop dev.neerajpilot.dart_ffi_execmem_repro
adb shell am start -n \
  dev.neerajpilot.dart_ffi_execmem_repro/.MainActivity
```

With the restriction allowed, it displays `Callback result: 42`. With the
restriction enabled, the expected signature is:

```text
error: mprotect failed: 13 (Permission denied)
signal 6 (SIGABRT)
```

The source line in `virtual_memory_posix.cc` varies between Dart releases.

## Controlled reproduction on stock Android

The harness can reproduce the relevant denial without GrapheneOS. The filter
is irreversible and process-wide until the app exits. Use it only in this test
application.

Negative control:

```sh
flutter build apk --release --target-platform android-arm64 \
  --target lib/harness_main.dart \
  --dart-define=DENY_EXECMEM=true \
  --dart-define=CALLBACK_API=none
```

`Pointer.fromFunction`:

```sh
flutter build apk --release --target-platform android-arm64 \
  --target lib/harness_main.dart \
  --dart-define=DENY_EXECMEM=true \
  --dart-define=CALLBACK_API=pointer
```

`NativeCallable.isolateLocal`:

```sh
flutter build apk --release --target-platform android-arm64 \
  --target lib/harness_main.dart \
  --dart-define=DENY_EXECMEM=true \
  --dart-define=CALLBACK_API=native
```

Install and start each generated APK with:

```sh
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb logcat -c
adb shell am force-stop dev.neerajpilot.dart_ffi_execmem_repro
adb shell am start -n \
  dev.neerajpilot.dart_ffi_execmem_repro/.MainActivity
adb logcat -d -v brief
```

Unknown `CALLBACK_API` values fail explicitly. `DENY_EXECMEM=true` also fails
explicitly outside release mode or Android ARM64.

## Isolated Cronet scenario

The nested project starts a Dart HTTP server on the loopback interface, makes
a Cronet request to it, and requires HTTP 204. It never contacts the public
internet. Both builds disable the Google Play Services provider so the
reproduction also works without sandboxed Google Play.

Allowed control:

```sh
cd cronet_repro
flutter pub get
flutter build apk --release --target-platform android-arm64 \
  --dart-define=DENY_EXECMEM=false \
  --dart-define=cronetHttpNoPlay=true
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am force-stop dev.neerajpilot.cronet_execmem_repro
adb shell am start -n \
  dev.neerajpilot.cronet_execmem_repro/.MainActivity
```

The app should display `Cronet loopback result: HTTP 204`.

Targeted denial:

```sh
flutter build apk --release --target-platform android-arm64 \
  --dart-define=DENY_EXECMEM=true \
  --dart-define=cronetHttpNoPlay=true
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb logcat -c
adb shell am force-stop dev.neerajpilot.cronet_execmem_repro
adb shell am start -n \
  dev.neerajpilot.cronet_execmem_repro/.MainActivity
adb logcat -d -v brief
```

This variant should abort with the same `mprotect/EACCES` signature.

## Why Cronet reaches this path

Cronet reports network events through Java callbacks. The generated Dart/JNI
proxy converts a Dart callback into a C-compatible function pointer with
`Pointer.fromFunction`, which enters the same Dart VM trampoline path as the
minimal reproduction. Cronet 1.9.0 is recorded here only as the tested package
version; this repository is not responding to an upstream claim that the
version changed executable-memory behavior.

## Relevant sources

- [Ente issue #5723](https://github.com/ente/ente/issues/5723)
- [Dart VM FFI trampoline allocation](https://github.com/dart-lang/sdk/blob/475f448a716a7cc0ae4092835fb1466bf8324908/runtime/vm/ffi_callback_metadata.cc#L171-L223)
- [Cronet 1.9.0 generated callback](https://github.com/dart-lang/http/blob/5d94ef52582867e077bf41c3fa20fb8b1d1d834e/pkgs/cronet_http/lib/src/jni/jni_bindings.dart#L70-L74)
- [GrapheneOS exploit-protection documentation](https://grapheneos.org/features#exploit-mitigations)
- [`media_kit`'s independently documented case](https://github.com/media-kit/media-kit/issues/1015)
- [`media_kit` package-level workaround](https://github.com/media-kit/media-kit/pull/1022)

## License

[MIT](LICENSE)
