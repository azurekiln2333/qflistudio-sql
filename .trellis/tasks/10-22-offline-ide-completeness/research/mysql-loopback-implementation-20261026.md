# OHOS same-device MySQL sharing source change

Date: 2026-10-26. Source implementation only. No SDK, native compiler,
dependency resolution, build, signing, device, HDC, channel control or runtime
tests were invoked for this change. Existing task and product acceptance gaps
remain open.

## Change boundary

The OHOS SQL application previously used only its private Unix socket.
The new explicit service control shares the same managed Oracle MySQL data
with other applications on the same device through IPv4 loopback only.
Changes are limited to QfliMysqlRuntime.ets, QfliMysqlNative.ets,
qfli_mysql_napi.cpp, module.json5 and this note. Dart UI, permission inspection,
offline policy and tests have separate owners. Shared native ABI implementations
and sibling applications remain outside this change.

## Channel contract

Channel: `qfli_sql/mysql`. Methods take no arguments:

- `sharingStatus`: inspect the currently owned service without starting it.
- `startSharing`: provision privately and start the loopback service.
- `stopSharing`: stop the managed server and preserve its data directory.

Each returns a map with `supported` (boolean), `running` (boolean),
`host` (`127.0.0.1`), `port` (integer `3306`), `database` (`qfli_shared`),
`username` (`qfli_app`), `password` (string) and `error` (string).
The password is returned only after authenticated readiness succeeds.
Start/stop failures normally return a stopped/error map. Unexpected channel
exceptions use MYSQL_SHARING_STATUS_FAILED, MYSQL_SHARING_START_FAILED or
MYSQL_SHARING_STOP_FAILED with fixed messages that contain no credentials.
Probe roots reject sharing. App disposal still terminates the managed child.
The ordinary `stop` method and internal Unix clients retain their API behavior.

## Fail-closed provisioning

Normal startup remains `skip-networking`. A sharing request first starts that
private server and requires existing child ownership. It queries the actual
`@@skip_networking` value before provisioning. It then persists two independent
256-bit passwords from installed SDK cryptoFramework.createRandom /
generateRandomSync(32). Their hexadecimal encoding avoids SQL literal escaping
ambiguity. The private JSON credential file is atomically replaced after fsync.
The native bridge applies fchmod(0600) before writing any credential bytes.
An unsuccessful write never installs the credentials in runtime state.

On that network-disabled server the runtime creates qfli_shared, recreates
qfli_app@127.0.0.1, grants privileges only on qfli_shared.*, and changes
root@localhost to the persisted internal password. Both account statements
explicitly select caching_sha2_password for the Oracle MySQL 8.4.6 client
authentication contract. Recreating the dedicated account clears old privileges
and role memberships for that exact identity.
An authenticated root query then rejects empty-password root or anonymous
accounts. Any failed statement or failed verification prevents TCP startup.
The root password is never part of the public sharing map.

Only after successful provisioning and verification does the runtime stop/reap
the private server. A bind probe detects an occupied/unavailable port 3306.
The subsequent managed restart uses `skip-networking=OFF`,
`bind-address=127.0.0.1`, `port=3306` and `skip-name-resolve`.
There is no alternate-port fallback or LAN listener. The build source already
sets WITH_MYSQLX=OFF. `loose-mysqlx=OFF` also disables that plugin if a future
image includes it without breaking images where its option does not exist.

The design deliberately does not depend on normal startup `--init-file`.
Primary source review of Oracle mysql-8.4.6/sql/mysqld.cc found that normal
init-file SQL failure does not have the initialize-thread abort behavior.
The network socket also binds before process_bootstrap. Private provisioning
and a confirmed stop/restart avoid treating init-file execution as an
authentication barrier.

## Authentication, recovery and readiness

All runtime query/script/shutdown calls pass the current internal root password.
The NAPI methods accept an optional trailing password and use the existing
password-aware native C++ overloads. Existing callers that omit the argument
retain their empty-password behavior for isolated private probes.

The credential file is written before ALTER USER. After process interruption,
the runtime loads that same file. If a newly spawned owned server is explicitly
network-disabled, readiness may retry an empty password to recover interruption
before ALTER USER. No empty-password retry is possible for a TCP-enabled start.
An already reachable unowned server cannot be shared through this operation.
Server diagnostics redact both persisted passwords before returning log tails.

The runtime retains its previous root password until a new-password query
confirms authentication. It performs that query even when the provisioning
script throws, because ALTER USER may already have completed. Authentication
success switches shutdown to the new password even if the script later reports
failure. Authentication failure retains the previous shutdown password. The
persisted credentials remain available for private recovery in either case.
A pending termination error remains visible when an authenticated probe still
finds a running server.

Sharing readiness opens a real C API TCP connection to 127.0.0.1:3306 as the
dedicated account and selects qfli_shared. It verifies the observed server
version, port, bind address, skip_networking, DATABASE() and CURRENT_USER().
The C API uses bounded connection/read/write timeouts and its own thread scope.
This verifies account authentication and actual listener configuration rather
than returning intended configuration as readiness evidence.

Service controls use the existing operation queue. Their private stop helper
uses the existing graceful-first stop/reap machinery without awaiting the queue
from inside the queue. Failure to confirm termination preserves ownership,
blocks new queries and reports a retryable stopping error. The data directory
and credentials survive stop/restart. An ordinary later query can restart the
server privately after sharing has stopped.

## Static checks and remaining acceptance

Source searches confirmed the native password overloads, the Oracle header
include/link path, every direct ArkTS native query/script/shutdown call, the
WITH_MYSQLX=OFF build setting and installed SDK generateRandomSync declaration.
`git diff --check` on the four product files passed after editing.

Independent review and authored source tests remain required. No runtime test
result is claimed. A fresh named grant is still required for any SDK/native
build or device acceptance. Existing packaged MySQL images predate this NAPI
source change and must be rebuilt/staged through the approved pipeline before
the new methods can function on a device. Verify port conflict, first install,
legacy private-data migration, durable credentials, interruption around root
password change, repeated start/stop, background/disposal, Unix worksheet access,
sibling-app login, wrong-password rejection, account scope, IPv4 loopback-only
listening, absence of MySQLX listening and actual INTERNET permission metadata.
Cross-application loopback policy and app background survival require actual
phone evidence. HAP packaging alone cannot establish either behavior.
