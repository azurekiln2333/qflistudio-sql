# Oracle MySQL macOS Helpers

The Runner build invokes `bundle.py` with Xcode's environment. It builds the
existing native client bridge and parent launcher, embeds the actual Oracle
server and its resources, relocates dependencies, then signs each helper before
the outer application's signing step. Python 3.9+, CMake 3.20+ and Xcode command
line tools are required. The script uses only Python's standard library.

## Inputs

Supply the complete official Oracle **8.4.6** macOS distributions for the
architectures in Xcode's `ARCHS`. Retain archive provenance and verify the
upstream download before extracting; this repository does not supply or claim
verified Apple archives. Each SDK must contain `bin/mysqld`, development headers,
native client/dependency libraries, `share` and the upstream `LICENSE`.

```bash
export QFLI_MYSQL_MACOS_ARM64=/verified/mysql-8.4.6-macos-arm64
export QFLI_MYSQL_MACOS_X64=/verified/mysql-8.4.6-macos-x86_64
export QFLI_MYSQL_SOURCE=/verified/mysql-8.4.6-source
flutter build macos
```

Only requested architectures need SDKs. The pinned source supplies RapidJSON
headers, as on Windows/Linux. Use `runtime.json` in an SDK to retain its archive
URL/hash/license provenance. The final manifest also hashes the exact SDK native
inputs and all signed helper files.

The app's `MACOSX_DEPLOYMENT_TARGET` must meet the minimum encoded in **every**
native input. Runner currently declares 10.15; a newer Oracle distribution can
require raising that setting in every Xcode configuration before building.
The packager rejects incompatible inputs and never silently raises the target.

## Layout And Signing

For each ABI, the app contains:

```text
Contents/Helpers/QfliMySql-{arm64,x64}.app/Contents/
  MacOS/qfli_mysql_launcher
  MacOS/mysqld
  Frameworks/libqfli_mysql_bridge.dylib
  Frameworks/<Oracle/dependency dylibs>
  PlugIns/<server plugins and configuration>
  Resources/{share,docs,licenses,LICENSE,...}
Contents/Resources/qfli-mysql-runtime.json
```

CMake BundleUtilities resolves the full native dependency chain using the SDK.
Non-system dependencies must come from that SDK or the staged helper. Native
files are thinned and checked for CPU, macOS load commands and minimum OS.
Final library references use `@loader_path`, including the bridge loaded inside
the outer Flutter process; `@executable_path` would refer to Runner in that case.
Native RPATHs are removed, and the complete internal closure is checked.

The packager signs dylibs/plugins first, then executables and the helper app.
Helpers use only app-sandbox and inherit entitlements. Network client/server
permissions belong to Runner and cover the private Unix socket. The signing
identity is Xcode's `EXPANDED_CODE_SIGN_IDENTITY`; an empty identity uses ad hoc
signing. A real identity uses hardened runtime and timestamping. No library
validation exemption or public TCP listener is added.

Runtime discovery chooses the current process ABI, including x64 under Rosetta.
It injects explicit server, bridge, launcher, resource and plugin paths into the
existing private lifecycle. `QFLI_MYSQL_BUNDLE` still selects the existing flat
`{bin,lib,share}` desktop layout. Signed files remain in the app; writable data
stays in the app's Application Support directory. Final signed-file hashes live
outside the helper signature to avoid a circular resource hash.

## Verification

```bash
python3 -m unittest discover -s native/mysql/macos -p test_bundle.py -v
```

These portable tests validate native headers, OS/CPU rejection, relocation and
dependency containment. They do not establish an Apple build or execution pass.
On an Apple host, inspect both requested helpers, verify their signatures, then
run real SQL CRUD/persistence/stop and application-death recovery in the packaged
sandboxed application. Unsandboxed command line tests cannot establish sandbox
behavior. This delivery has no Apple build/sign/run evidence on the Windows host.

For standalone lifecycle/adapter fixtures in the helper layout, use its
Resources as the bundle, supply the bridge and launcher paths, and set
`QFLI_MYSQL_TEST_SERVER` and `QFLI_MYSQL_TEST_PLUGIN_DIRECTORY` to the helper's
mysqld and PlugIns paths. Production never reads these test environment inputs.
