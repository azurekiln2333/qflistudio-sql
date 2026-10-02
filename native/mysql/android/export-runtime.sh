#!/usr/bin/env bash
set -euo pipefail
WORK="${QFLI_MYSQL_ANDROID_WORK:?Set the Android work directory}"
NDK="${QFLI_ANDROID_NDK:?Set Android NDK 27 root}"
ABI="${QFLI_ANDROID_ABI:-x86_64}"
BUILD="$WORK/android-build-$ABI"
SOURCE="$WORK/mysql-8.4.6"
OUTPUT="${QFLI_MYSQL_ANDROID_OUTPUT:?Set an empty runtime export directory}"
case "$ABI" in
  x86_64) TRIPLE=x86_64-linux-android;;
  arm64-v8a) TRIPLE=aarch64-linux-android;;
  *) exit 64;;
esac
test ! -e "$OUTPUT"
PREBUILT="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
[[ -d "$PREBUILT" ]] || PREBUILT="$NDK/toolchains/llvm/prebuilt/windows-x86_64"
mkdir -p "$OUTPUT/bin" "$OUTPUT/lib" "$OUTPUT/share/english" "$OUTPUT/share/icu" "$OUTPUT/licenses"
cp "$BUILD/runtime_output_directory/mysqld" "$OUTPUT/bin/mysqld"
cp "$BUILD/qfli-runtime/bin/qfli_mysql_launcher" "$OUTPUT/bin/qfli_mysql_launcher"
cp "$BUILD/qfli-runtime/lib/libqfli_mysql_bridge.so" "$OUTPUT/lib/"
cp "$PREBUILT/sysroot/usr/lib/$TRIPLE/libc++_shared.so" "$OUTPUT/lib/"
cp "$BUILD/share/english/errmsg.sys" "$OUTPUT/share/english/"
cp -a "$SOURCE/share/charsets" "$OUTPUT/share/"
cp -a "$SOURCE/extra/icu/icudt77l" "$OUTPUT/share/icu/"
cp "$SOURCE/LICENSE" "$OUTPUT/licenses/mysql-LICENSE"
cp "$SOURCE/Docs/INFO_SRC" "$OUTPUT/licenses/mysql-INFO_SRC"
cp "$WORK/openssl-3.5.3/LICENSE.txt" "$OUTPUT/licenses/openssl-LICENSE.txt"
cp "$PREBUILT/sysroot/usr/include/c++/v1/__config" "$OUTPUT/licenses/libcxx-config"
cp "$NDK/NOTICE" "$OUTPUT/licenses/android-ndk-NOTICE"
printf '%s\n' 'Oracle MySQL 8.4.6; Android API 28; OpenSSL 3.5.3; NDK 27.0.12077973' > "$OUTPUT/PROVENANCE.txt"
for file in "$OUTPUT/bin/"* "$OUTPUT/lib/"*; do
  /usr/bin/llvm-strip-18 --strip-debug "$file"
done
find "$OUTPUT" -type f -exec chmod 644 {} +
chmod 755 "$OUTPUT/bin/"*
printf 'Exported Android Oracle runtime: %s\n' "$OUTPUT"
