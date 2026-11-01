SDK=/root/qfli-mysql-port/ohos-sdk/llvm/lib/aarch64-linux-ohos
echo "=== archives under llvm/lib/aarch64-linux-ohos ==="
ls -la "$SDK"/*.a 2>/dev/null
echo "=== archives under .../c++ ==="
ls -la "$SDK/c++"/*.a 2>/dev/null
echo "=== which libc++.a vs c++/libc++_static.a differ? ==="
cmp -s "$SDK/libc++.a" "$SDK/c++/libc++_static.a" && echo "identical" || echo "different or missing"
echo "=== does libc++.a already contain __cxa_guard_* / __gxx_personality / _Unwind ==="
for a in "$SDK/libc++.a" "$SDK/libc++_static.a" "$SDK/libc++abi.a" "$SDK/c++/libc++_static.a"; do
  [ -f "$a" ] || continue
  echo "--- $a ---"
  llvm-nm-18 "$a" 2>/dev/null | grep -m3 -E "__cxa_guard_acquire|__gxx_personality|_Unwind_Resume" | head -3
done
