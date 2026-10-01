# Native SQLite Platforms

The primary local engine uses the retained upstream `third_party/sqlite/sqlite3.c`
and the existing C script bridge. SQL parsing and execution are performed by
SQLite. No evaluator, external SQLite command or cloud service is used.

## Build and Load

`native/pubspec.yaml` is a local Flutter FFI plugin. Android builds the C library
with NDK 27 and CMake; every ELF LOAD segment is linked for 16 KiB pages. Windows
and Linux plugin CMake files provide the shared library to Flutter's normal
bundle installer. Windows packages `qfli_sqlite.dll` beside the runner; Linux
packages `lib/libqfli_sqlite.so`.

iOS/macOS CocoaPods stage the retained C sources inside each local pod root.
The static pod compiles both C objects, exposes global symbols, and adds app
linker retention flags for every FFI function. Dart uses process symbols on
Apple platforms. Apple compilation and execution are unverified without Xcode.

Android opens `libqfli_sqlite.so` from the packaged native library directory.
Desktop development tests may use `native/build/<operatingSystem>/` or set
`QFLI_SQLITE_LIBRARY` to an explicit library. A missing library is an error.
OHOS continues to use its existing native method channel.

## Verification

```powershell
cmake -S native/runtime -B native/build/windows -G Ninja -DCMAKE_C_COMPILER=<gcc>
cmake --build native/build/windows
flutter test --no-pub
flutter test --no-pub integration_test/sql_native_test.dart integration_test/sql_workbench_test.dart -d emulator-5560
```

On 2026-10-02, the Windows MinGW C build and all 48 Flutter tests passed in the
owning SQL repository. The 7 new FFI cases execute the real engine and cover the editor
entry, persisted scripts, Unicode/quotes/embedded NUL parameters, SQL NULL,
parameter mismatch, multiple-statement rejection, transactional multi-statement
scripts with retained results, output limits, actual grid
mutations and missing-library failure.

All 6 Android x86_64 backend integration cases passed on emulator-5560, API 37 with
16 KiB pages. They cover script persistence and SQL errors, structured parameter
queries, structured scripts, workspace CRUD, shadowed rowid identity and WITHOUT ROWID behavior.
The APK includes arm64-v8a, armeabi-v7a and x86_64 SQLite libraries; inspection
confirmed 0x4000 alignment for every native LOAD segment in all three ABIs.
This is application FFI evidence, not shell execution. Android ARM devices,
Linux GUI and Apple hosts were unavailable. Full Windows Flutter GUI builds
require missing Visual Studio C++ tools; the native engine and Flutter tests
were run. Analysis of changed Dart files was clean. Full analysis retains four
pre-existing informational lints in sql_document_service/sql_workbench_page.

The default-workbench UI case also passed after the AVD was restarted with
3 GiB RAM and retained disk data. It opens the actual default repository,
edits a cell, checks the persisted row, executes SQL, saves the query and
reopens the query library. Compact navigation is located by its SQL tooltip.
The combined Android run passed all 7 cases. A preceding run on the 2 GiB AVD
was interrupted after MemAvailable reached zero and system services timed out.

Local Oracle MySQL outside OHOS remains a separate integration gap. SQLite is
identified as SQLite and is never reported as MySQL.
