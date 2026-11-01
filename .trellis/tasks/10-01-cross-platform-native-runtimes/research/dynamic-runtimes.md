# Research: Dynamic Runtime Platform Integration

- Query: Audit the real bundled engines in qfli_lua, qfli_python, qfli_web, and qfli_dart; identify missing non-OHOS integration and a faithful implementation path.
- Scope: internal, with upstream references recorded in the repositories
- Date: 2026-10-01
- Method: Read-only source/config/spec inspection. No tests, builds, device probes, or source changes were performed.

## Findings

### Authoritative Platform Matrix

Entries describe the inspected source and packaging integration, not a new execution verification. Web Linux/macOS wiring was added by a concurrent implementer during this research; its newly observed integration is noted below.

| Product / engine | Windows | Linux | Android | macOS | iOS | OHOS |
| --- | --- | --- | --- | --- | --- | --- |
| Lua / official Lua 5.4.8 C VM | CMake build/bundle and FFI loader present | CMake build/bundle and FFI loader present | Gradle builds bundled C sources; FFI loads .so | FFI expects a dylib, but no native target or packaging | No native target; loader falls through to .so | Native CMake target and .so FFI integration present |
| Python / MicroPython 1.24.1 C compiler/VM | No native target or channel registration | Native host smoke harness only; no product target/channel | Shared C core + Kotlin/JNI + channel registered | No native target or channel registration | No native target or channel registration | C core + ArkTS/NAPI + channel registered |
| Web / upstream Nginx 1.31.6 C server | Official exe retained; CMake packaging and discovery present | New CMake build/bundle/discovery observed; not verified here | Three PIE binaries retained; nativeLibraryDir discovery present | New source build/Xcode bundle hook/discovery observed; not verified here | No Nginx integration; WebForge Dart server and Safari preview only | Two binaries and executableBinaryPaths retained; historical app exec failure is documented |
| Dart / dart_eval 0.8.5 | Same portable Dart runner; no OS gate | Same portable Dart runner; no OS gate | Same portable Dart runner; no OS gate | Same portable Dart runner; no OS gate | Same portable Dart runner; no OS gate | Same portable Dart runner; no OS gate |

Dart is **not** currently a C/C++ interpreter. Its parser, compiler, and EVC runtime come from Dart packages. WebForge fallback is also implemented in Dart. These distinctions must remain explicit; their existence cannot prove native Nginx or an official Dart VM implementation.

### Lua

All paths in this subsection are relative to `D:/MyNewProjects/qfli_lua`.

- `native/third_party/lua-5.4.8/src/`: retained official Lua engine sources, compiled without `lua.c` and `luac.c` executables.
- `native/src/qfli_lua.c`: VM lifecycle, project-relative I/O wrappers, output capture, syntax check, bytecode dump, timeout, cancellation.
- `native/src/qfli_lua.h:13`: result layout: `{int status; char *output; char *error; size_t output_length; size_t error_length;}`.
- `native/src/qfli_lua.h:22`: APIs: `const char *qfli_lua_version(void)`; `QfliLuaResult *qfli_lua_run(file, project_dir, timeout_ms)`; `qfli_lua_run_with_token(file, project_dir, timeout_ms, token)`; `qfli_lua_token_new/cancel/free`; `qfli_lua_check(file)`; `qfli_lua_compile(file, output_file)`; `qfli_lua_free(result)`.
- `lib/lua_toolchain.dart:81`: `run/startRun({required file, required projectDirectory, timeLimit=10s})`; `check(file)`; `compile(file, outputFile)`; `version()`. Calls execute on worker isolates; cancellation token lives until native completion. `LuaToolResult` has `status/output/error`.
- `lib/lua_toolchain.dart:152`: library discovery uses Windows `libqfli_lua.dll`, macOS `libqfli_lua.dylib`, otherwise `libqfli_lua.so`; desktop executable root, `lib/`, then checkout `native/build/<platform>`. iOS has no `DynamicLibrary.process()` path.
- `windows/CMakeLists.txt:54,78`, `linux/CMakeLists.txt:59,97`: build and install the `qfli_lua_engine` shared library. Android `android/app/build.gradle.kts:23` builds `native/CMakeLists.txt`; NDK 27.0.12077973 is pinned. OHOS `ohos/entry/src/main/cpp/CMakeLists.txt` includes the native target.
- `native/CMakeLists.txt:11`: C11 shared target; `LUA_COMPAT_5_3`; Unix enables POSIX and dlopen, links m/dl. The C bridge already handles Windows monotonic clocks and MSVC atomics (`native/src/qfli_lua.c:12,33,52`).
- `ios/Runner.xcodeproj/project.pbxproj`, `macos/Runner.xcodeproj/project.pbxproj`, both Apple bootstrap files: no Lua source build/link/embed entries. Adding only a loader filename will not package an engine.
- `lib/main.dart:38`: metadata currently marks runtime available globally, despite missing Apple packaging.

Minimal faithful change: reuse these exact retained Lua sources for Apple. Add a local native/FFI plugin or explicit Xcode/CocoaPods source target. iOS can statically link and expose kept/exported symbols through `DynamicLibrary.process()`; macOS can link similarly or embed a signed dylib/framework and discover its actual app-bundle path. Preserve binary output lengths, per-state path handling, and cooperative cancellation. No host Lua installation is required.

Supplementary script caveat: `lib/lua_runner.dart:19,39,119` also accepts JS/MJS/TS/SH. Those use host `node/deno/tsx/ts-node/sh/bash/powershell` on desktop and reject mobile execution. No bundled JavaScript/TypeScript/Shell engine exists here. This is separate from its fully bundled primary Lua path and must not be described as portable bundled script support.

### Python

All paths in this subsection are relative to `D:/MyNewProjects/qfli_python`.

- `native/third_party/micropython/`: retained upstream MicroPython source checkout; fixed version is 1.24.1 (`ecfdd5d`).
- `native/micropython_embed/`: generated self-contained C engine, headers, qstr/module definitions, and port configuration. It is the source package consumed by Android and the host smoke harness.
- `native/src/qfli_py_bridge.c`: source compilation/execution, fresh VM per request, import paths, heap, result ownership, serialized global engine access.
- `native/src/qfli_py_stdio.c`, `qfli_py_hal.c`, `qfli_py_file.c`: finite stdin, separate output/error, clocks/delay, project file streams and descriptor cleanup.
- `native/src/qfli_py_bridge.h:55`: `QfliPyRunResult qfli_py_run(const char *source, const char *stdin_text, int heap_kb, const char *project_dir, const char *entry_file, int compile_only)`; `void qfli_py_result_free(QfliPyRunResult *)`; `const char *qfli_py_version(void)`.
- Result is returned **by value**, with fields in order: `int exit_code; char *output; char *error; int truncated`. Output is owned, NUL-terminated UTF-8; error may be NULL. It is not a length-carrying binary-output API.
- `lib/python_runner.dart:47,71,159,235`: only `MethodChannel('qfli_py/native')`. Methods `available`, `run`, `checkSyntax`; no platform selection gate and no FFI backend. Request `{source:String, stdin:String, heapKb:int, projectPath:String, entryFile:String}`. Probe `{available:bool, version:String, detail:String}`. Run/check response `{exitCode:int, output:String, error:String|null, truncated:bool}`.
- `android/app/src/main/kotlin/com/azurekiln/qfli/pyflow/QfliPyNative.kt`: loadLibrary + single background executor (1 MiB stack), UTF-8 byte-array JNI, main-thread response. `android/app/build.gradle.kts:35,46` points to `native/android/CMakeLists.txt`; source list includes JNI wrapper only for Android.
- `native/src/qfli_py_napi.cpp`, `native/ohos/QfliPyNative.ets`, `ohos/entry/src/main/ets/plugins/QfliPyNative.ets`, `EntryAbility.ets`: OHOS adapters. Keep both ArkTS copies synchronized.
- `windows/CMakeLists.txt`, `linux/CMakeLists.txt`, Apple bootstrap/project files: no engine build/bundle/channel adapter. Current global available metadata at `lib/main.dart:30` does not establish desktop/Apple execution.

Portability work is required beyond registering a channel:

- Root `native/CMakeLists.txt` is OHOS-specific: it unconditionally compiles NAPI, links `libace_napi.z.so`/hilog/static C++, and defaults qstr preprocessing to an OHOS target triple. Do not include this file unchanged in desktop builds.
- The Android source target is a better template for a platform-neutral core: reuse the same generated C inputs and exclusion list, then choose JNI/NAPI/FFI adapters conditionally. Parallel target builds must read generated inputs rather than rewrite one shared source directory.
- `native/src/qfli_py_bridge.c:39,73,357`: pthread mutex; Windows requires an app platform abstraction or equivalent locking.
- `native/src/qfli_py_hal.c:214,242,263`: clock_gettime/nanosleep; Windows needs monotonic/performance counter, real-time, and bounded-delay adapters.
- `native/src/qfli_py_file.c:14,33,78,93,242`: unistd/realpath/POSIX descriptors, O_CLOEXEC/O_NOFOLLOW, canonical containment. Windows paths need actual handle-based canonical resolution, drive/UNC/separator/case handling, UTF-8 to UTF-16 OS calls, and equivalent read/write/seek/stat/close behavior. `_fullpath` alone does not resolve symlink escape.
- `native/micropython_embed/py/reader.c:70`: upstream POSIX module reader also calls open/read/close. It must receive the same Windows I/O adaptation; porting only user `open()` misses imports.
- `native/port/mpconfigport.h:17,163,182`: alloca include, mp_off_t=long, and non-Android identity hardcoded to OHOS. Keep source and generated port header in sync; select correct Windows/iOS/macOS/Linux identity and file-offset types.
- `native/micropython_embed/shared/runtime/gchelper_generic.c`: GNU register-asm implementation. Android already sets `MICROPY_GCREGS_SETJMP=1`; use that upstream fallback for new compilers/Apple ABIs. MSVC also needs appropriate NLR setjmp selection. Upstream `native/third_party/micropython/ports/windows/mpconfigport.h:174,210,223,234` contains authoritative Windows compiler/type/alloca examples.
- Existing C header has no Windows export macro; a DLL FFI route must export its API explicitly.

Minimal faithful change: split core build ownership from OHOS wrappers, add FFI desktop/Apple bindings and bundled platform artifacts (or native channel adapters preserving the same response), and run C calls off the Flutter UI thread. A small pointer-result wrapper can simplify FFI ABI ownership, while preserving the existing JNI/NAPI API. Do not use a system Python process or switch to CPython: the established engine is MicroPython. Existing unsupported pip/CPython extensions, interactive stdin, and cancellation stay explicit.

### Web / Nginx

All paths in this subsection are relative to `D:/MyNewProjects/qfli_web`.

- `vendor/nginx/nginx-1.31.6.tar.gz`: retained official C source archive; source and Windows archive hashes are in `vendor/nginx/SOURCE.json`. Android compatibility patches and glob sources/licenses are retained under `vendor/nginx/`.
- `assets/runtime/nginx/windows/nginx.exe`: retained official Windows binary. `windows/CMakeLists.txt:75` installs it/license to `data/nginx/`.
- `android/app/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86_64}/libnginx_exec.so`: PIE executables; Gradle `useLegacyPackaging=true` and `MainActivity.kt:16` expose `applicationInfo.nativeLibraryDir` through `qflistudio/platform.nginxPath`.
- `ohos/entry/libs/{arm64-v8a,x86_64}/libnginx_exec.so`, `ohos/entry/src/main/module.json5:14`, `EntryAbility.ets:50`: packaged binaries, executable declarations, path adapter. Historical EACCES and pending post-manifest execution are recorded in `vendor/nginx/VALIDATION.md`; they are not a new verified pass.
- Initial `lib/services/web_runtime.dart:12` snapshot supported discovery only for Android, OHOS, Windows; Linux/macOS/iOS returned null. Auto falls back to `WebDevServer`; explicit Nginx fails. Only OHOS auto handles native exec EACCES. At final research inspection, concurrent changes extended desktop discovery to Linux `data/nginx/nginx` and macOS `Contents/Helpers/nginx`, with platform-specific checkout paths. iOS still has no native discovery.
- `lib/services/nginx_session.dart:46`: `Future<NginxSession> start(String projectPath, {required String executable, WebProjectConfig? configuration})`; uses subprocess `-v`, `-t`, start and stop. Native public listener proxies to a private Dart middleware for safe files, diagnostics/SSE and HTTPS upstreams.
- `lib/services/web_runtime_session.dart:3,15`: event `(method:String, path:String, status:int, elapsed:Duration)`; session extends shared `WebPreviewSession`, adding `engineName` and `requests`; shared preview exposes `url`, `debugStream`, `stop()`.
- `scripts/build_nginx_android.sh`, `scripts/build_nginx_ohos.sh`, `scripts/nginx_cc.sh`: fixed-source cross builds and Windows-tool invocation from WSL. Concurrently added `scripts/build_nginx_desktop.sh` builds retained upstream source natively on Linux/macOS, verifies its archive hash, and selects macOS ARCHS/deployment target; `scripts/bundle_nginx_macos.sh` stages/signs the helper and license. No iOS build/lifecycle script was observed.
- `ios/Runner/AppDelegate.swift:16`: only in-app Safari `openUrl` registration, no Nginx path or engine. macOS both existing entitlements contain network client/server. Concurrently observed `linux/CMakeLists.txt:99` source-build target/install and `macos/Runner.xcodeproj/project.pbxproj:305` bundle script hook.

Faithful Linux/macOS approach now being implemented concurrently: build retained upstream source with local C toolchain, retain the native configuration assumptions, bundle binary/license in an app-relative executable location, and add discovery. No system-installed nginx requirement. Verify helper architecture/signing/dependencies and update integration tests to use that bundled path rather than Windows-only constants/skips. The new script disables gzip/rewrite/auth-basic to avoid external library requirements; these differences must remain consistent with generated Nginx configuration.

iOS requires a different native lifecycle design. Existing subprocess `NginxSession` cannot be made portable solely by adding discovery. The retained upstream `src/core/nginx.c:200,352,400` owns main/signals/event loop; `src/os/unix/ngx_process_cycle.c:301,332,724` exits the host process even in single-process shutdown. A faithful in-process port must replace process exits/signals, expose controlled start/stop/wakeup, isolate globals, and clean all native state before restart. Calling upstream main on a thread is unsafe. WebForge fallback alone does not implement native Nginx. Apple execution/build validation requires an Apple toolchain; no such tests were attempted here.

### Dart

All paths in this subsection are relative to `D:/MyNewProjects/qfli_dart`.

- `pubspec.yaml`: dart_eval=0.8.5, analyzer=8.4.1, dart_style=3.1.3, pubspec_parse=1.6.0.
- `lib/dart_runner.dart:13,67,103,119`: `DartProgramRunner.run({required projectPath, required entryFile}) -> Future<ProgramRunResult?>`; loads sources, compiles with `Compiler`, executes `Runtime.ofProgram` in an isolate, returns stdout/stderr streams + exit future + cancel. Cancellation kills isolate and returns 130; compile/start failures 127; runtime failures 1. No MethodChannel, FFI, or native source requirement.
- `lib/dart_project_sources.dart:12`: file-backed project loader, relative and same-project package imports; excludes hidden files/build directories/symlinks.
- `lib/dart_tools.dart:26,53`: `CompiledDartProgram {Uint8List bytecode; String entryUri}`; compile produces EVC bytes through same compiler. `format` and syntax diagnostics use real package parser/formatter.
- `lib/main.dart:32`: runtimeStatus is currently unavailable despite wired portable runner. Spec deliberately keeps that status until target build/execution evidence exists.

No platform-specific compiler registration is currently missing for dart_eval on native Flutter targets. Target execution can still be unverified. Replacing it with official Dart C++ VM would be a separate engine change: no bundled official source/SDK embedding/build adapter exists in this product. Preserve accurate dart_eval compatibility claims and do not describe EVC as official Dart VM bytecode.

### Existing Verification Harnesses / Prerequisites

| Product | Existing harness | Requirements and limits |
| --- | --- | --- |
| Lua | native CTest `native/test/qfli_lua_test.c`; `test/lua_app_test.dart`, `test/lua_editor_tools_test.dart`; `bin/qfli_lua.dart`; `tool/lua_device_probe.dart` | CMake + matching C compiler/ABI; host library staged to loader path. Real VM tests cover source/bytecode, modules/I/O, streams/binary bytes, errors, timeout/cancel. Desktop tests do not establish Apple packaging. |
| Python | `native/tests/run_host.sh`, `native/tests/smoke.c`; Android JNI debug self-checks; Dart tests | Linux GCC/libm/pthread and `/proc/self/fd` for existing harness (WSL usable); harness includes imports, I/O/modes/path errors, finite stdin, exit overflow, compile-only, reset/descriptor cleanup. Current Dart Python suites mock the MethodChannel and do not prove any host native engine. Windows needs a portable harness and actual DLL/FFI run. |
| Web | `test/nginx_session_test.dart`; `test/web_dev_server_test.dart`; `tool/nginx_smoke.dart` | Retained real binary, loopback ports and project files; native tests currently skip non-Windows (`:115,184,224,254`). Extend to bundled Linux/macOS runtime. Device probe requires a connected supported device and reports PASS only after HTTP, proxy, WebSocket, SSE, stop/restart. |
| Dart | `test/dart_app_test.dart`, `test/dart_tools_test.dart`, `test/dart_tools_page_test.dart` | Flutter/Dart SDK and resolved packages. Tests execute real dart_eval including EVC reload, source imports, errors and cancel. These are stronger than channel mocks but do not prove iOS/macOS target packaging/runtime behavior. |

Windows native app builds need Visual Studio C++ tools (engine-only CMake may also use MinGW/Clang). Linux app builds need Flutter Linux, GTK development packages and C/C++ tools; native engine/server tests can run separately under WSL. Android uses the installed NDK 27 and Gradle/JBR. Apple source integration needs Xcode/SDKs, CocoaPods or equivalent native package build support, and signing where applicable. Skip unavailable target tests as requested; do not infer a target pass from another platform's result.

### Related Specs and Upstream References

- Read `.trellis/workflow.md` and qfli_sql backend/frontend indexes and cross-layer guide. Generic indexes mostly remain placeholders; engine contracts live in the sibling repos.
- `qfli_lua/.trellis/spec/backend/lua-toolchain.md`: exact native result layout, packaging/ABI, cancellation limits and validation contract.
- `qfli_python/.trellis/spec/backend/native-python-runtime.md`, `android-build.md`: exact channel/API, upstream engine identity, shared input/error/file lifetime, JNI/threading and native validation.
- `qfli_web/.trellis/spec/backend/web-runtime.md`: native selection, middleware/proxy boundary, preview/openUrl lifecycle and native claims.
- `qfli_dart/.trellis/spec/frontend/dart-tools.md`: EVC compiler, parser/formatter, isolate/cancel and target-verification status.
- Lua 5.4.8: https://www.lua.org/ftp/lua-5.4.8.tar.gz (release/hash recorded in `qfli_lua/native/README.md`).
- MicroPython 1.24.1: retained upstream Windows port and generated `genhdr/mpversion.h`; project version `ecfdd5d` is returned by real engine headers.
- Nginx 1.31.6: https://nginx.org/download/nginx-1.31.6.tar.gz and .zip; hashes recorded in `qfli_web/vendor/nginx/SOURCE.json`; Termux patch provenance retained there.

## Caveats / Not Found

- No tests or builds were run in this research subtask. Prior recorded PASS counts in READMEs are historical documentation, not fresh task evidence.
- No Apple-native Lua/Python build or registration, no iOS Nginx package/lifecycle, and no official Dart C++ VM embedding were found. Linux/macOS Nginx source integration appeared during concurrent implementation and has not been validated in this research.
- Full Flutter app sources exist for all standard native platforms, but skeleton platform directories alone do not prove bundled runtime support.
- OHOS runtime health is not revalidated here. Native Nginx exec limitations documented in that product remain materially different from an in-process Lua/Python VM.
- Supplementary JS/TS/Shell execution in qfli_lua relies on external desktop commands. Browser JavaScript in qfli_web uses browser execution; Nginx is an HTTP engine, not a JS interpreter.
