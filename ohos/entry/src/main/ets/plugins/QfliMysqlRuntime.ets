import qfliMysql from 'libqfli_mysql.so';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import deviceInfo from '@ohos.deviceInfo';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { childProcessManager, common } from '@kit.AbilityKit';

export interface QfliMysqlColumn {
  name: string;
  nativeType: number;
  binary: boolean;
}

export interface QfliMysqlResponse {
  available: boolean;
  exitCode: number;
  error: string;
  sqlState: string;
  affectedRows: number;
  truncated: boolean;
  columns: Array<string>;
  columnInfo: Array<QfliMysqlColumn>;
  rows: Array<Array<string | null>>;
}

export interface QfliMysqlScriptResponse extends QfliMysqlResponse {
  results: Array<QfliMysqlResponse>;
}

export interface QfliMysqlSharingStatus {
  supported: boolean;
  running: boolean;
  host: string;
  port: number;
  database: string;
  username: string;
  password: string;
  error: string;
}

interface MysqlCredentials {
  rootPassword: string;
  sharingPassword: string;
}

interface QfliMysqlChildStatus {
  state: 'unknown' | 'running' | 'exited';
  exitCode: number;
}

// Structured result of the native fork start. On failure with owned=true the
// child could not be confirmed terminated and pendingPid must be cleaned through
// the lifecycle (stop()/dispose()).
interface MysqlStartResult {
  pid: number;
  failed: boolean;
  owned: boolean;
  pendingPid: number;
  errno: number;
  error: string;
}

// Result of the API26 native-child capability probe. Named so ArkTS does not
// need an anonymous object literal as a type. query is 'ok' when the API ran,
// 'unavailable' when it was missing or threw.
interface MysqlCapabilityResult {
  query: 'ok' | 'unavailable';
  supported: boolean;
  error: string;
  // API26 Ark child process support. Separate from native-child support: an Ark
  // child is a fresh OS process that can load the native server through the
  // normal native-library mechanism.
  arkQuery: 'ok' | 'unavailable';
  arkSupported: boolean;
  arkError: string;
}

// Result of a bounded child stop/reap attempt. Named so ArkTS does not need an
// anonymous object literal as a type.
interface QfliMysqlStopResult {
  confirmed: boolean;
  code: number;
  error: Error | undefined;
}

interface QfliMysqlModule {
  query(socket: string, schema: string, source: string,
    params: Array<string | null>, password: string): Promise<QfliMysqlResponse>;
  executeScript(socket: string, schema: string, source: string,
    password: string): Promise<QfliMysqlScriptResponse>;
  shutdown(socket: string, password: string): Promise<QfliMysqlResponse>;
  sharingProbe(password: string): Promise<QfliMysqlResponse>;
  loopbackPortAvailable(): boolean;
  protectFile(descriptor: number): void;
  startChild(entryParams: string, logPath: string): MysqlStartResult;
  // Debug-only preload instrumentation and host (present only in probe builds).
  protoProbe?(): Record<string, Object>;
  preloadStart?(entryParams: string): MysqlPreloadResult;
  registerChild(pid: number): void;
  completeRegisteredChild(pid: number, exitCode: number): void;
  releaseChild(pid: number): void;
  pollChild(pid: number): QfliMysqlChildStatus;
  signalChild(pid: number, force: boolean): void;
  version(): string;
}

// Result of the debug-only preloaded start (fork + direct entry, no exec).
// Same structured ownership contract as MysqlStartResult.
interface MysqlPreloadResult {
  pid: number;
  failed: boolean;
  owned: boolean;
  pendingPid: number;
  errno: number;
  error: string;
}

interface MysqlChildPayload {
  arguments: Array<string>;
  exitFile: string;
  icuDataDirectory: string;
}

interface MysqlMarker {
  version: string;
}

interface MysqlAssets {
  version: string;
  files: Array<string>;
}

const MYSQL_VERSION = '8.4.6';
const MYSQL_ENTRY = 'libqfli_mysql_server.so:QfliMysqlMain';
const nativeModule = qfliMysql as QfliMysqlModule | undefined;

type MysqlHostKind = 'nativeChild' | 'fork';

export class QfliMysqlRuntime {
  private readonly context: common.UIAbilityContext;
  // Mutable only through overrideRootForProbe(), before any child/init is owned.
  private root: string;
  private socket: string;
  // True once overrideRootForProbe() has been used, to reject later switching.
  private rootOverridden: boolean = false;
  private ready: boolean = false;
  // closing blocks new queries while stop() runs; it is cleared once the server
  // is fully stopped so a later start in the same app is allowed again.
  private closing: boolean = false;
  private disposed: boolean = false;
  private host: MysqlHostKind | undefined;
  private pid: number | undefined;
  private processExit: string | undefined;
  private starting: Promise<void> | undefined;
  private stopping: Promise<void> | undefined;
  private queue: Promise<void> = Promise.resolve();
  private sharingRequested: boolean = false;
  private sharingError: string = '';
  private rootPassword: string = '';
  private credentials: MysqlCredentials | undefined;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.root = `${context.filesDir}/mysql`;
    this.socket = `${this.root}/mysql.sock`;
  }

  // Debug/test-only isolated root selection. Used ONLY by the OHOS integration
  // probe so an experimental Oracle initialization/start/stop never touches the
  // production data under <filesDir>/mysql. Requirements:
  //  - must be called BEFORE any server/init is owned (no pid, not ready, not
  //    starting/stopping, not closing/disposed);
  //  - the path must be a single validated directory segment directly under
  //    context.filesDir, whose name starts with the probe prefix;
  //  - a non-empty runKey of safe characters is required for a unique per-run
  //    directory; no copying, deleting, or adopting existing data.
  // The normal lib/main.dart path never calls this and keeps <filesDir>/mysql.
  configureProbeRoot(runKey: string): string {
    if (this.rootOverridden || this.pid !== undefined || this.ready ||
      this.starting !== undefined || this.stopping !== undefined ||
      this.closing || this.disposed) {
      throw new Error('The Oracle MySQL runtime root cannot be changed now.');
    }
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(runKey)) {
      throw new Error('Invalid Oracle MySQL probe run key.');
    }
    const base = this.context.filesDir;
    // Short prefix: a Unix sun_path is 107 bytes plus NUL, and the full socket
    // path is <root>/mysql.sock. "mysql-probe" keeps headroom for the runKey.
    const prefix = `${base}/mysql-probe/`;
    const candidate = `${prefix}${runKey}`;
    if (!candidate.startsWith(prefix) || candidate.slice(prefix.length) !== runKey ||
      candidate.includes('..') || candidate.includes('//')) {
      throw new Error('Invalid Oracle MySQL probe root path.');
    }
    // Reject an existing per-run directory: each run gets a unique root, and the
    // probe must not adopt or overwrite a previous run's data.
    if (fs.accessSync(candidate)) {
      throw new Error('Oracle MySQL probe root already exists for this run.');
    }
    // Validate the actual Unix socket path length (sun_path is 107 + NUL).
    const socketPath = `${candidate}/mysql.sock`;
    if (socketPath.length > 107) {
      throw new Error('Oracle MySQL probe socket path is too long for a Unix socket.');
    }
    this.makeDirectory(`${base}/mysql-probe`);
    this.root = candidate;
    this.socket = socketPath;
    this.rootOverridden = true;
    return this.root;
  }

  // Returns the actual native runtime root currently in use, so the probe can
  // record PID/log evidence without guessing app-global vs module paths.
  runtimeRoot(): string {
    return this.root;
  }

  query(schema: string, source: string,
    params: Array<string | null>): Promise<QfliMysqlResponse> {
    if (this.closing || this.disposed) return Promise.reject(new Error('Oracle MySQL is closing.'));
    const operation = this.queue.then(async (): Promise<QfliMysqlResponse> => {
      await this.ensureStarted();
      const response = await this.module().query(this.socket, schema, source, params, this.rootPassword);
      if (!response.available) this.ready = false;
      return response;
    });
    this.queue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  executeScript(schema: string, source: string): Promise<QfliMysqlScriptResponse> {
    if (this.closing || this.disposed) return Promise.reject(new Error('Oracle MySQL is closing.'));
    const operation = this.queue.then(async (): Promise<QfliMysqlScriptResponse> => {
      await this.ensureStarted();
      const response = await this.module().executeScript(this.socket, schema, source, this.rootPassword);
      if (!response.available) this.ready = false;
      return response;
    });
    this.queue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  sharingStatus(): Promise<QfliMysqlSharingStatus> {
    const operation = this.queue.then((): Promise<QfliMysqlSharingStatus> => this.inspectSharing());
    this.queue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  startSharing(): Promise<QfliMysqlSharingStatus> {
    if (this.closing || this.disposed || this.rootOverridden) {
      return Promise.resolve(this.sharingSnapshot(false, 'MySQL sharing is unavailable in this runtime.'));
    }
    const operation = this.queue.then(async (): Promise<QfliMysqlSharingStatus> => {
      try {
        if (this.sharingRequested) {
          const current = await this.inspectSharing();
          if (current.running) return current;
          await this.stopSharingChild();
        }
        this.sharingRequested = false;
        this.sharingError = '';
        await this.ensureStarted();
        if (this.pid === undefined || this.host === undefined) {
          throw new Error('Refusing to share a MySQL server outside this runtime ownership.');
        }
        await this.provisionSharing();
        await this.stopSharingChild();
        if (!this.module().loopbackPortAvailable()) {
          this.sharingError = 'Loopback port 127.0.0.1:3306 is occupied or unavailable.';
          throw new Error('Loopback port 127.0.0.1:3306 is occupied or unavailable.');
        }
        this.sharingRequested = true;
        await this.ensureStarted();
        const status = await this.inspectSharing();
        if (!status.running) throw new Error(status.error);
        return status;
      } catch (_) {
        if (this.sharingError.length === 0) {
          this.sharingError = 'Could not start MySQL sharing on 127.0.0.1:3306. Check port availability and local MySQL startup.';
        }
        try {
          await this.stopSharingChild();
          this.sharingRequested = false;
        } catch (_) {
          this.closing = true;
          this.sharingError = 'MySQL sharing failed and server termination is unconfirmed. Retry stopping the service.';
        }
        return this.sharingSnapshot(false, this.sharingError);
      }
    });
    this.queue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  stopSharing(): Promise<QfliMysqlSharingStatus> {
    const operation = this.queue.then(async (): Promise<QfliMysqlSharingStatus> => {
      try {
        await this.stopSharingChild();
        this.sharingRequested = false;
        this.sharingError = '';
        if (!this.disposed && this.stopping === undefined) this.closing = false;
      } catch (_) {
        this.closing = true;
        this.sharingError = 'MySQL server termination is unconfirmed. Retry stopping the service.';
      }
      return this.inspectSharing();
    });
    this.queue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  private sharingSnapshot(running: boolean, error: string): QfliMysqlSharingStatus {
    return {
      supported: nativeModule !== undefined && !this.rootOverridden && !this.disposed,
      running: running,
      host: '127.0.0.1',
      port: 3306,
      database: 'qfli_shared',
      username: 'qfli_app',
      password: running ? (this.credentials?.sharingPassword ?? '') : '',
      error: error,
    };
  }

  private async inspectSharing(): Promise<QfliMysqlSharingStatus> {
    if (!this.sharingRequested || this.credentials === undefined || this.pid === undefined) {
      return this.sharingSnapshot(false, this.sharingError);
    }
    try {
      if (this.childStatus(this.pid).state !== 'running') {
        return this.sharingSnapshot(false, 'The MySQL sharing process is not running.');
      }
      const result = await this.module().sharingProbe(this.credentials.sharingPassword);
      const row = result.rows.length === 1 ? result.rows[0] : [];
      if (!result.available || result.exitCode !== 0 || row.length !== 6 ||
        row[0] === null || !/^8\.4\.6(?:-|$)/.test(row[0]) || row[1] !== '3306' ||
        row[2] !== '127.0.0.1' || row[3] !== '0' || row[4] !== 'qfli_shared' ||
        row[5] !== 'qfli_app@127.0.0.1') {
        return this.sharingSnapshot(false, 'Authenticated MySQL loopback readiness failed.');
      }
      return this.sharingSnapshot(true, this.sharingError);
    } catch (_) {
      return this.sharingSnapshot(false, 'Authenticated MySQL loopback readiness failed.');
    }
  }

  private async stopSharingChild(): Promise<void> {
    if (this.pid !== undefined) {
      const result = await this.stopChild(this.pid);
      if (!result.confirmed) throw new Error('MySQL server termination is unconfirmed.');
      this.pid = undefined;
      this.host = undefined;
    }
    this.ready = false;
  }

  private async provisionSharing(): Promise<void> {
    const privateStatus = await this.module().query(this.socket, '',
      'SELECT @@skip_networking', [], this.rootPassword);
    if (!privateStatus.available || privateStatus.exitCode !== 0 ||
      privateStatus.rows.length !== 1 || privateStatus.rows[0][0] !== '1') {
      throw new Error('MySQL account provisioning requires a network-disabled server.');
    }
    if (this.credentials === undefined) {
      const credentials: MysqlCredentials = {
        rootPassword: this.randomPassword(), sharingPassword: this.randomPassword(),
      };
      this.writeText(`${this.root}/sharing-credentials.json`, JSON.stringify(credentials));
      this.credentials = credentials;
    }
    const credentials = this.credentials;
    const script = [
      'CREATE DATABASE IF NOT EXISTS `qfli_shared`',
      "DROP USER IF EXISTS 'qfli_app'@'127.0.0.1'",
      `CREATE USER 'qfli_app'@'127.0.0.1' IDENTIFIED WITH caching_sha2_password BY '${credentials.sharingPassword}'`,
      "GRANT ALL PRIVILEGES ON `qfli_shared`.* TO 'qfli_app'@'127.0.0.1'",
      `ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${credentials.rootPassword}'`,
    ].join(';\n');
    let result: QfliMysqlScriptResponse | undefined;
    try {
      result = await this.module().executeScript(this.socket, '', script, this.rootPassword);
    } catch (_) {}
    const verified = await this.module().query(this.socket, '',
      "SELECT COUNT(*) FROM mysql.user WHERE (User = 'root' OR User = '') AND authentication_string = ''",
      [], credentials.rootPassword);
    if (verified.available) this.rootPassword = credentials.rootPassword;
    if (result === undefined || !result.available || result.exitCode !== 0 ||
      !verified.available || verified.exitCode !== 0 ||
      verified.rows.length !== 1 || verified.rows[0][0] !== '0') {
      throw new Error('MySQL account provisioning could not be verified.');
    }
  }

  private randomPassword(): string {
    const bytes = cryptoFramework.createRandom().generateRandomSync(32).data;
    let password = '';
    for (let index = 0; index < bytes.length; index++) password += bytes[index].toString(16).padStart(2, '0');
    return password;
  }

  // Coalesces concurrent stop calls through one promise. closing is set for the
  // duration and cleared only after a confirmed full stop; on failure the
  // runtime retains ownership so a later stop/restart cannot orphan a live
  // server and no concurrent query slips through mid-shutdown.
  stop(): Promise<void> {
    if (this.stopping !== undefined) return this.stopping;
    this.closing = true;
    this.stopping = this.stopInternal();
    return this.stopping;
  }

  private async stopInternal(): Promise<void> {
    // Explicitly typed error state: ArkTS rejects `unknown` locals.
    let failure: Error | undefined;
    let confirmed = true;
    try {
      await this.queue;
      if (this.starting !== undefined) {
        try {
          await this.starting;
        } catch (_) {}
      }
      if (this.pid !== undefined) {
        const result = await this.stopChild(this.pid);
        confirmed = result.confirmed;
        if (result.error !== undefined) failure = result.error;
      }
    } catch (error) {
      failure = error as Error;
      confirmed = false;
    }
    this.stopping = undefined;
    this.ready = false;
    if (confirmed) {
      // Terminal status was observed: ownership is released so a later
      // stop/restart cannot hold a stale PID and closing is cleared.
      this.pid = undefined;
      this.host = undefined;
      this.closing = false;
      this.sharingRequested = false;
    }
    // While termination is unconfirmed, ownership and closing are retained so a
    // later stop can retry and no query slips in against a live server.
    if (failure !== undefined) throw failure;
  }

  // Stops one owned child with bounded async escalation. Reports whether the
  // child reached a confirmed terminal state and any diagnostic error, without
  // deciding ownership release (that is stopInternal's job).
  private async stopChild(pid: number): Promise<QfliMysqlStopResult> {
    const exitFile = this.processExit ?? `${this.root}/server.exit`;
    const owned = this.host === 'fork' || this.host === 'nativeChild';
    let shutdownRequested = false;
    if (this.readExit(exitFile) === undefined && this.ready) {
      try {
        const response = await this.module().shutdown(this.socket, this.rootPassword);
        shutdownRequested = response.available && response.exitCode === 0;
      } catch (_) {}
    }
    if (!owned) {
      try {
        await this.waitExit(exitFile, 30000);
        return { confirmed: true, code: 0, error: undefined };
      } catch (error) {
        return { confirmed: false, code: 0, error: error as Error };
      }
    }
    // Graceful-first: if we asked the server to shut down, wait for its exit
    // record WITHOUT signalling, so Oracle removes its pid file and exits 0.
    // Only escalate (SIGTERM -> SIGKILL) if it does not arrive in time.
    if (shutdownRequested) {
      const graceful = await this.awaitOwnedExit(pid, exitFile, 30000);
      if (graceful !== undefined) {
        return this.finishOwned(pid, graceful);
      }
    }
    const reaped = await this.reapOwned(pid, exitFile);
    if (!reaped.confirmed) {
      return { confirmed: false, code: reaped.code, error: reaped.error };
    }
    return this.finishOwned(pid, reaped.code);
  }

  // Waits for an owned child to exit on its own (no signal). Returns the exit
  // code when a terminal state is observed, or undefined on timeout.
  private async awaitOwnedExit(pid: number, exitFile: string,
    timeout: number): Promise<number | undefined> {
    const deadline = Date.now() + timeout;
    while (Date.now() < deadline) {
      const status = await this.settleStatus(pid, exitFile);
      if (status.state === 'exited') return status.exitCode;
      if (status.state === 'unknown') {
        const record = this.readExit(exitFile);
        if (record !== undefined) return record;
      }
      await this.delay(100);
    }
    return undefined;
  }

  // Releases a confirmed-dead owned child and reports any nonzero-exit error.
  private finishOwned(pid: number, code: number): QfliMysqlStopResult {
    try {
      this.module().releaseChild(pid);
    } catch (error) {
      return { confirmed: true, code,
        error: new Error(this.diagnostic(`Oracle MySQL release failed: ${error}`, code)) };
    }
    if (code !== 0 && this.ready) {
      return { confirmed: true, code,
        error: new Error(this.diagnostic('Oracle MySQL shutdown', code)) };
    }
    return { confirmed: true, code, error: undefined };
  }

  // Signals an owned child and polls until it exits, escalating to SIGKILL after
  // a grace period. Returns the observed exit code and whether a terminal state
  // was actually confirmed. Never claims success without observing one.
  private async reapOwned(pid: number, exitFile: string): Promise<QfliMysqlStopResult> {
    // Settle BEFORE signalling: a framework child may already be dead, and its
    // verified identity would make signal_child reject it. An already-exited
    // record is a complete, successful reap with no signal needed.
    let status = await this.settleStatus(pid, exitFile);
    if (status.state === 'exited') return { confirmed: true, code: status.exitCode, error: undefined };
    if (status.state === 'unknown') {
      const record = this.readExit(exitFile);
      if (record !== undefined) return { confirmed: true, code: record, error: undefined };
    }
    // Graceful signal only when the verified child is still reported running.
    this.signalSettled(pid, false, exitFile);
    const gracefulDeadline = Date.now() + 15000;
    while (Date.now() < gracefulDeadline) {
      status = await this.settleStatus(pid, exitFile);
      if (status.state === 'exited') return { confirmed: true, code: status.exitCode, error: undefined };
      if (status.state === 'unknown') {
        const record = this.readExit(exitFile);
        if (record !== undefined) return { confirmed: true, code: record, error: undefined };
      }
      await this.delay(100);
    }
    this.signalSettled(pid, true, exitFile);
    const forcedDeadline = Date.now() + 10000;
    while (Date.now() < forcedDeadline) {
      status = await this.settleStatus(pid, exitFile);
      if (status.state === 'exited') return { confirmed: true, code: status.exitCode, error: undefined };
      if (status.state === 'unknown') {
        const record = this.readExit(exitFile);
        if (record !== undefined) return { confirmed: true, code: record, error: undefined };
      }
      await this.delay(100);
    }
    return { confirmed: false, code: 125, error: new Error(this.diagnostic('Oracle MySQL shutdown timed out', undefined)) };
  }

  // Signals only when the child is still reported running, and tolerates a
  // concurrent exit (ESRCH or a rejected already-gone identity) by falling back
  // to the exit file. Never signals an unverified/reused PID: signal_child
  // enforces that, and a rejection is treated as "already gone", not forced.
  private signalSettled(pid: number, force: boolean, exitFile: string): void {
    const status = this.module().pollChild(pid);
    if (status.state === 'exited') return;
    try {
      this.module().signalChild(pid, force);
    } catch (_) {
      // The verified process is gone or unverified; completion is settled from
      // the exit record on the next loop iteration.
    }
  }

  // Resolves a child's typed status for one poll step. Registered native-child
  // processes are not waitpid children, so once their process is gone they are
  // completed from the exit record so the real code replaces the sentinel.
  private async settleStatus(pid: number, exitFile: string): Promise<QfliMysqlChildStatus> {
    let status = this.module().pollChild(pid);
    if (status.state === 'exited' && this.host === 'nativeChild') {
      const record = this.readExit(exitFile);
      if (record !== undefined) {
        try {
          this.module().completeRegisteredChild(pid, record);
        } catch (_) {}
        status = this.module().pollChild(pid);
        if (status.state === 'exited' && status.exitCode === record) return status;
      }
    }
    return status;
  }

  // Terminal shutdown: mark disposed BEFORE awaiting stop so a concurrent query
  // sees the closed state immediately. Unlike stop(), dispose() is final.
  async dispose(): Promise<void> {
    this.disposed = true;
    await this.stop();
  }

  private module(): QfliMysqlModule {
    if (nativeModule === undefined) throw new Error('Oracle MySQL native module is unavailable.');
    if (nativeModule.version().length === 0) {
      throw new Error('本地 Oracle MySQL 需要 HarmonyOS arm64 设备。');
    }
    return nativeModule;
  }

  // Host selection. The device-reported capability is authoritative over the
  // static docs: if the OS reports native child processes are supported on this
  // device (API26 childProcessManager.isNativeChildProcessSupported), use that
  // public API. Otherwise fall back to the forked-child exec host. Both run the
  // same server entry and JSON.
  private selectHost(): MysqlHostKind {
    const capability = this.queryNativeChildCapability();
    const host: MysqlHostKind = capability.supported ? 'nativeChild' : 'fork';
    // Record the exact capability result so the device probe shows what the OS
    // actually reported, not what the docs imply.
    try {
      this.writeText(`${this.root}/capability.log`,
        `deviceType=${deviceInfo.deviceType} sdkApi=${deviceInfo.sdkApiVersion} ` +
        `native query=${capability.query} supported=${capability.supported} ` +
        `error=${capability.error} ` +
        `ark query=${capability.arkQuery} supported=${capability.arkSupported} ` +
        `error=${capability.arkError} host=${host}\n`);
    } catch (_) {}
    return host;
  }

  // Queries the OS capability probes. Distinguishes an actual API26 `false`
  // result from the API being missing or throwing: only the latter uses the
  // documented device-type fallback.
  private queryNativeChildCapability(): MysqlCapabilityResult {
    let query: 'ok' | 'unavailable' = 'unavailable';
    let supported = false;
    let error = '';
    try {
      supported = childProcessManager.isNativeChildProcessSupported() === true;
      query = 'ok';
    } catch (caught) {
      const fallback = deviceInfo.deviceType === '2in1' || deviceInfo.deviceType === 'tablet';
      supported = fallback;
      error = `${caught}`;
    }
    let arkQuery: 'ok' | 'unavailable' = 'unavailable';
    let arkSupported = false;
    let arkError = '';
    try {
      arkSupported = childProcessManager.isArkChildProcessSupported() === true;
      arkQuery = 'ok';
    } catch (caught) {
      arkError = `${caught}`;
    }
    return { query, supported, error, arkQuery, arkSupported, arkError };
  }

  // Debug-only: returns the native prototype instrumentation result.
  protoProbeNative(): Record<string, Object> {
    const native = this.module();
    if (native.protoProbe === undefined) {
      throw new Error('The prototype probe is unavailable in this build.');
    }
    return native.protoProbe();
  }

  // Debug-only: start the private preloaded server in a forked child (no exec)
  // for the isolated probe root, and adopt it into the same owned-client
  // tracking as the fork+exec host. Used only by startHostChild when the
  // isolated probe root is active; the full lifecycle (assets/config/init exit/
  // markers/readiness/restart) stays in startInternal.
  private startPreloadedChild(initialize: boolean, exitFile: string): MysqlStartResult {
    const payload: MysqlChildPayload = {
      arguments: ['mysqld', `--defaults-file=${this.root}/my.cnf`],
      exitFile: exitFile,
      icuDataDirectory: `${this.root}/share/icu`,
    };
    if (initialize) payload.arguments.push('--initialize-insecure');
    const native = this.module();
    if (native.preloadStart === undefined) {
      throw new Error('The preload host is unavailable in this build.');
    }
    const started = native.preloadStart(JSON.stringify(payload));
    // The native preload host returns the same structured result as startChild:
    // {pid, failed, owned, pendingPid, errno, error}.
    const result: MysqlStartResult = {
      pid: started.pid,
      failed: started.failed,
      owned: started.owned,
      pendingPid: started.pendingPid,
      errno: started.errno,
      error: started.error,
    };
    return result;
  }

  private async ensureStarted(): Promise<void> {
    if (this.closing) throw new Error('Oracle MySQL is closing.');
    if (this.ready) return;
    if (this.starting !== undefined) return this.starting;
    this.starting = this.startInternal();
    try {
      await this.starting;
    } finally {
      this.starting = undefined;
    }
  }

  private async startInternal(): Promise<void> {
    this.module();
    // Beginning-of-start cleanup: if a previous start failed while still owning
    // a live child, reap it BEFORE any file rewrite or new child spawn, so a
    // retry cannot overwrite the PID or leak a second server.
    if (this.pid !== undefined && (this.host === 'fork' || this.host === 'nativeChild')) {
      const status = this.childStatus(this.pid);
      if (status.state === 'running') {
        await this.reapChild(this.pid);
      } else if (status.state === 'exited') {
        try {
          this.module().releaseChild(this.pid);
        } catch (_) {}
      }
      this.pid = undefined;
      this.host = undefined;
    }
    this.makeDirectory(this.root);
    if (fs.accessSync(`${this.root}/sharing-credentials.json`)) {
      const credentials = JSON.parse(fs.readTextSync(`${this.root}/sharing-credentials.json`)) as MysqlCredentials;
      if (!/^[0-9a-f]{64}$/.test(credentials.rootPassword) ||
        !/^[0-9a-f]{64}$/.test(credentials.sharingPassword)) {
        throw new Error('MySQL sharing credentials are invalid.');
      }
      this.credentials = credentials;
      this.rootPassword = credentials.rootPassword;
    }
    const markerPath = `${this.root}/initialized.json`;
    const initialized = fs.accessSync(markerPath);
    if (initialized) {
      const marker = JSON.parse(fs.readTextSync(markerPath)) as MysqlMarker;
      if (marker.version !== MYSQL_VERSION) {
        throw new Error(`Oracle MySQL data version ${marker.version} requires a migration.`);
      }
    }
    this.makeDirectory(`${this.root}/tmp`);
    this.makeDirectory(`${this.root}/plugins`);
    await this.installAssets();
    this.writeText(`${this.root}/my.cnf`, this.configuration());
    const initializeExit = `${this.root}/initialize.exit`;
    if (!initialized) {
      this.makeDirectory(`${this.root}/data`);
      const previousExit = this.readExit(initializeExit);
      const existingData = fs.listFileSync(`${this.root}/data`).length > 0;
      if (existingData && previousExit !== 0) {
        throw new Error(this.diagnostic('Oracle MySQL initialization is incomplete', previousExit));
      }
      if (!existingData) {
        this.removeIfExists(initializeExit);
        this.pid = await this.startHostChild(true, initializeExit);
        const exitCode = await this.waitExit(initializeExit, 120000);
        // Always reap the initialization child, even when the exit record
        // arrived first.
        await this.reapChild(this.pid);
        this.pid = undefined;
        if (exitCode !== 0) throw new Error(this.diagnostic('Oracle MySQL initialization', exitCode));
      }
      const marker: MysqlMarker = { version: MYSQL_VERSION };
      this.writeText(markerPath, JSON.stringify(marker));
    }

    if (this.closing) throw new Error('Oracle MySQL is closing.');
    this.removeIfExists(`${this.root}/server.exit`);
    const existing = await this.module().query(this.socket, '', 'SELECT VERSION()', [], this.rootPassword);
    if (this.isReady(existing)) {
      const serverPid = this.readExit(`${this.root}/mysql.pid`);
      if (serverPid === undefined || serverPid <= 1) {
        throw new Error('Oracle MySQL is reachable but its process identifier is missing.');
      }
      // Preserve ownership when the reachable server is the child this runtime
      // already started. Only a genuinely different server is unowned, because
      // a transient query failure may have set ready=false while the owned
      // child is still alive.
      if (this.pid === serverPid && (this.host === 'fork' || this.host === 'nativeChild') &&
        this.childStatus(serverPid).state === 'running') {
        this.ready = true;
        this.processExit = `${this.root}/server.exit`;
        return;
      }
      // A server this runtime did not start: rely on the socket and exit file.
      this.pid = serverPid;
      this.host = undefined;
      this.ready = true;
      this.processExit = `${this.root}/server.exit`;
      return;
    }
    if (this.pid !== undefined && (this.host === 'fork' || this.host === 'nativeChild')) {
      await this.reapChild(this.pid);
      this.pid = undefined;
      this.removeIfExists(`${this.root}/server.exit`);
    }
    this.pid = await this.startHostChild(false, `${this.root}/server.exit`);
    const deadline = Date.now() + 120000;
    while (Date.now() < deadline) {
      const exitCode = this.readExit(`${this.root}/server.exit`);
      if (exitCode !== undefined) {
        await this.reapChild(this.pid);
        this.pid = undefined;
        throw new Error(this.diagnostic('Oracle MySQL startup', exitCode));
      }
      if (this.closing) {
        if (this.pid !== undefined) await this.reapChild(this.pid);
        this.pid = undefined;
        throw new Error('Oracle MySQL is closing.');
      }
      if (this.pid !== undefined && this.childStatus(this.pid).state === 'exited') {
        await this.reapChild(this.pid);
        this.pid = undefined;
        throw new Error(this.diagnostic('Oracle MySQL exited without a startup result', undefined));
      }
      let response = await this.module().query(this.socket, '', 'SELECT VERSION()', [], this.rootPassword);
      if (!this.sharingRequested && !response.available && this.rootPassword.length > 0 &&
        this.pid !== undefined && this.host !== undefined) {
        response = await this.module().query(this.socket, '', 'SELECT VERSION()', [], '');
        if (this.isReady(response)) this.rootPassword = '';
      }
      if (this.isReady(response)) {
        this.ready = true;
        return;
      }
      await this.delay(250);
    }
    if (this.pid !== undefined) await this.reapChild(this.pid);
    this.pid = undefined;
    throw new Error(this.diagnostic('Oracle MySQL startup timed out', undefined));
  }

  private isReady(response: QfliMysqlResponse): boolean {
    if (!response.available || response.exitCode !== 0) return false;
    if (response.rows.length !== 1 || response.rows[0].length !== 1 ||
      response.rows[0][0] === null || !/^8\.4\.6(?:-|$)/.test(response.rows[0][0])) {
      throw new Error('The local server is not the bundled Oracle MySQL 8.4.6.');
    }
    return true;
  }

  private async startHostChild(initialize: boolean, exitFile: string): Promise<number> {
    if (this.closing) throw new Error('Oracle MySQL is closing.');
    const payload: MysqlChildPayload = {
      arguments: ['mysqld', `--defaults-file=${this.root}/my.cnf`],
      exitFile: exitFile,
      icuDataDirectory: `${this.root}/share/icu`,
    };
    if (initialize) payload.arguments.push('--initialize-insecure');
    this.processExit = exitFile;
    const host = this.host ?? this.selectHost();
    this.host = host;
    const logPath = `${this.root}/${initialize ? 'initialize.log' : 'server.stderr.log'}`;
    if (host === 'fork') {
      // Use the validated preloaded private server host (fork + direct entry, no
      // denyable exec) whenever it is available. This is the production phone
      // host: direct launch exec is denied by the app sandbox (EACCES), so the
      // preload host is the supported path. The exec host remains only as a
      // fallback on builds without the preload host.
      const usePreload = this.module().preloadStart !== undefined;
      const started = usePreload
        ? this.startPreloadedChild(initialize, exitFile)
        : this.module().startChild(JSON.stringify(payload), logPath);
      if (started.failed || started.pid <= 1) {
        // A failed start may still own a live child. Adopt it so stop()/dispose()
        // clean it up; never leave an unreachable owned PID, and never fake
        // owned=false/pendingPid=-1.
        if (started.owned && started.pendingPid > 1) {
          this.pid = started.pendingPid;
          this.host = 'fork';
        }
        throw new Error(this.diagnostic(
          `Oracle MySQL start failed: ${started.error || `errno ${started.errno}`}`,
          undefined));
      }
      return started.pid;
    }
    const pid = await childProcessManager.startNativeChildProcess(MYSQL_ENTRY,
      { entryParams: JSON.stringify(payload) });
    // The native-child API creates the process; register it so poll/signal
    // manage it through the same owned-child table as the forked host.
    this.module().registerChild(pid);
    return pid;
  }

  // Returns the child's typed status. The native host retains terminal status
  // until releaseChild, so repeated calls stay idempotent. A server not started
  // by this runtime is unknown to the host and falls back to its exit record.
  private childStatus(pid: number): QfliMysqlChildStatus {
    if (this.host === 'fork' || this.host === 'nativeChild') {
      const status = this.module().pollChild(pid);
      if (status.state === 'exited' && this.host === 'nativeChild') {
        // A framework native-child is not a waitpid child; complete it from the
        // observed exit record once its process is gone.
        const record = this.readExit(this.processExit ?? `${this.root}/server.exit`);
        if (record !== undefined) {
          try {
            this.module().completeRegisteredChild(pid, record);
          } catch (_) {}
          return { state: 'exited', exitCode: record };
        }
      }
      return status;
    }
    const record = this.readExit(this.processExit ?? `${this.root}/server.exit`);
    return record === undefined ? { state: 'unknown', exitCode: 0 }
      : { state: 'exited', exitCode: record };
  }

  // Terminates and reaps an owned child, awaiting a confirmed terminal status
  // before releasing. Never discards a live PID. Bounded, never blocks on a
  // NAPI call.
  private async reapChild(pid: number): Promise<void> {
    if (this.host !== 'fork' && this.host !== 'nativeChild') return;
    const reaped = await this.reapOwned(pid, this.processExit ?? `${this.root}/server.exit`);
    if (!reaped.confirmed) {
      // Ownership is retained by the caller; the timeout diagnostic propagates.
      throw reaped.error ?? new Error(this.diagnostic('Oracle MySQL reap timed out', undefined));
    }
    try {
      this.module().releaseChild(pid);
    } catch (error) {
      throw new Error(this.diagnostic(`Oracle MySQL release failed: ${error}`, reaped.code));
    }
  }

  private async waitExit(path: string, timeout: number): Promise<number> {
    const deadline = Date.now() + timeout;
    while (Date.now() < deadline) {
      const code = this.readExit(path);
      if (code !== undefined) return code;
      if (this.pid !== undefined && this.childStatus(this.pid).state === 'exited') {
        // The child exited between the read above and the status poll. Re-read
        // the record once more before claiming it is missing.
        const settled = this.readExit(path);
        if (settled !== undefined) return settled;
        const status = this.childStatus(this.pid);
        throw new Error(this.diagnostic(
          `Oracle MySQL exited without an exit result (status ${status.state}, code ${status.exitCode})`,
          undefined));
      }
      await this.delay(100);
    }
    throw new Error(this.diagnostic('Oracle MySQL process timed out', undefined));
  }

  private readExit(path: string): number | undefined {
    if (!fs.accessSync(path)) return undefined;
    const text = fs.readTextSync(path).trim();
    if (!/^-?\d+$/.test(text)) throw new Error(`Invalid MySQL process status: ${path}`);
    return Number(text);
  }

  private diagnostic(action: string, code: number | undefined): string {
    // mysqld's own log plus the launcher/loader stderr logs. Exec or dlopen
    // failures happen before mysqld writes anything, so they only appear here.
    const logs = [`${this.root}/initialize.log`, `${this.root}/server.stderr.log`,
      `${this.root}/mysql.log`];
    let details = '';
    for (const logPath of logs) {
      if (!fs.accessSync(logPath)) continue;
      const size = fs.statSync(logPath).size;
      if (size === 0) continue;
      const text = fs.readTextSync(logPath, { offset: Math.max(0, size - 8192), length: 8192 });
      details += `\n[${logPath}]\n${text}`;
    }
    if (this.credentials !== undefined) {
      details = details.split(this.credentials.rootPassword).join('[redacted]');
      details = details.split(this.credentials.sharingPassword).join('[redacted]');
    }
    return `${action}${code === undefined ? '' : ` (exit ${code})`}.${details}`;
  }

  private configuration(): string {
    return [
      '[mysqld]',
      `basedir=${this.option(this.root)}`,
      `datadir=${this.option(`${this.root}/data`)}`,
      `socket=${this.option(this.socket)}`,
      `pid-file=${this.option(`${this.root}/mysql.pid`)}`,
      `log-error=${this.option(`${this.root}/mysql.log`)}`,
      `tmpdir=${this.option(`${this.root}/tmp`)}`,
      `plugin-dir=${this.option(`${this.root}/plugins`)}`,
      `lc-messages-dir=${this.option(`${this.root}/share`)}`,
      `character-sets-dir=${this.option(`${this.root}/share/charsets`)}`,
      this.sharingRequested ? 'skip-networking=OFF' : 'skip-networking',
      'bind-address=127.0.0.1',
      'port=3306',
      'loose-mysqlx=OFF',
      // Match TCP clients to qfli_app@127.0.0.1 without reverse-DNS host substitution.
      'skip-name-resolve',
      'skip-log-bin',
      'secure-file-priv=NULL',
      'performance-schema=OFF',
      'innodb-buffer-pool-size=32M',
      'innodb-log-buffer-size=8M',
      'innodb-redo-log-capacity=64M',
      'innodb-flush-method=fsync',
      'max-connections=16',
      'table-open-cache=128',
      'thread-cache-size=4',
      'log-error-verbosity=2',
      '',
    ].join('\n');
  }

  private option(value: string): string {
    return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n')}"`;
  }

  private makeDirectory(path: string): void {
    if (!fs.accessSync(path)) fs.mkdirSync(path, true);
  }

  private async installAssets(): Promise<void> {
    const bytes = await this.context.resourceManager.getRawFileContent('mysql/runtime.json');
    const manifest = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(bytes)) as MysqlAssets;
    if (manifest.version !== MYSQL_VERSION || !Array.isArray(manifest.files) ||
      !manifest.files.includes('share/english/errmsg.sys') ||
      !manifest.files.includes('share/charsets/Index.xml')) {
      throw new Error('Oracle MySQL runtime assets are incomplete or incompatible.');
    }
    for (const relative of manifest.files) {
      if (!relative.startsWith('share/') || relative.split('/').includes('..')) {
        throw new Error(`Invalid Oracle MySQL runtime asset: ${relative}`);
      }
      const destination = `${this.root}/${relative}`;
      this.makeDirectory(destination.slice(0, destination.lastIndexOf('/')));
      const data = await this.context.resourceManager.getRawFileContent(`mysql/${relative}`);
      this.writeAtomic(destination,
        data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength));
    }
  }

  private removeIfExists(path: string): void {
    if (fs.accessSync(path)) fs.unlinkSync(path);
  }

  private writeText(path: string, text: string): void {
    const bytes = new util.TextEncoder().encodeInto(text);
    this.writeAtomic(path, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
  }

  private writeAtomic(path: string, bytes: ArrayBuffer): void {
    const temporary = `${path}.tmp`;
    const file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      if (path.endsWith('/sharing-credentials.json')) this.module().protectFile(file.fd);
      let written = 0;
      while (written < bytes.byteLength) {
        const count = fs.writeSync(file.fd, bytes.slice(written));
        if (count <= 0) throw new Error(`Could not write MySQL runtime file: ${path}`);
        written += count;
      }
      fs.fsyncSync(file.fd);
    } finally {
      fs.closeSync(file);
    }
    fs.renameSync(temporary, path);
  }

  private delay(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve) => { setTimeout(resolve, milliseconds); });
  }
}
