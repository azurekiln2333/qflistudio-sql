# Apple native boundary

2026-11-17: HTTP HEAD to Oracle's official CDN returned 200 for:

- https://cdn.mysql.com/archives/mysql-8.4/mysql-8.4.6-macos15-arm64.tar.gz
  Content-Length: 166683072 bytes.
- https://cdn.mysql.com/archives/mysql-8.4/mysql-8.4.6-macos15-x86_64.tar.gz
  Content-Length: 171124041 bytes.

macos14 filenames returned 404. No full archive was downloaded or hash-verified.
Use the available official distributions rather than source-compiling MySQL.
The existing helper integration still needs native bridge/launcher compilation,
dependency relocation, deployment-target compatibility checks and signing.

iOS currently has the native/apple/podspec.rb SQLite source build only. It has
no Oracle server host or lifecycle implementation. The new CI script compiles
the same retained SQLite/bridge sources and defines with explicit iOS triples,
combines simulator architectures, and checks XCFramework metadata. This does
not create iOS MySQL functionality or establish device runtime acceptance.

The script requires a new output directory and does not delete caller data.
Local bash syntax passed. Actual Xcode compilation awaits the GitHub run.
