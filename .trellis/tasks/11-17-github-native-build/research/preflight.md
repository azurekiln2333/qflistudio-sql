# CI preflight

2026-11-17. User explicitly approved the revised mobile scope and immediate
implementation. A dedicated ci/native-build-20261117 branch was created.

Checks passed before the first push:
- actionlint 1.7.12 on .github/workflows/native-build.yml.
- Git Bash syntax for all tool/ci shell scripts and shared Oracle build scripts.
- Python compilation for package_native.py.
- git diff --check.
- scripts/ste-lint-zh.py README.md: zero hard violations.
- Pinned checkout/upload/setup-android commits resolved through GitHub API.
- Existing Git Credential Manager authentication belongs to azurekiln2333;
  GitHub Actions is enabled for the target repository. No credentials were logged.

An independent trellis-check agent identified draft wiring defects. These were
corrected: Android audit arguments and export layout, actual OHOS SQLite NAPI
target/staging, LLVM tool package, and iOS destructive output handling/duplicate
simulator slices. Subsequent agent requests failed with provider 429 limits.
The primary agent completed the final review and local checks.

OHOS toolchain overrides are propagated into CMake try-compile configurations,
matching the existing Android pattern, so runner SDK paths do not revert to
the original developer's Windows-mounted SDK path during compiler probes.

Local checks establish orchestration syntax, not cross-target compile success.
