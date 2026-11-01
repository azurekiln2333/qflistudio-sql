import qfliMysql from 'libqfli_mysql.so';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import deviceInfo from '@ohos.deviceInfo';
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

interface QfliMysqlModule {
  query(socket: string, schema: string, source: string,
    params: Array<string | null>): Promise<QfliMysqlResponse>;
  executeScript(socket: string, schema: string, source: string): Promise<QfliMysqlScriptResponse>;
  shutdown(socket: string): Promise<QfliMysqlResponse>;
  terminateChild(pid: number): void;
  isChildRunning(pid: number): boolean;
  version(): string;
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

export class QfliMysqlRuntime {
  private readonly context: common.UIAbilityContext;
  private readonly root: string;
  private readonly socket: string;
  private ready: boolean = false;
  private closing: boolean = false;
  private pid: number | undefined;
  private processExit: string | undefined;
  private starting: Promise<void> | undefined;
  private queue: Promise<void> = Promise.resolve();

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.root = `${context.filesDir}/mysql`;
    this.socket = `${this.root}/mysql.sock`;
  }

  query(schema: string, source: string,
    params: Array<string | null>): Promise<QfliMysqlResponse> {
    if (this.closing) return Promise.reject(new Error('Oracle MySQL is closing.'));
    const operation = this.queue.then(async (): Promise<QfliMysqlResponse> => {
      await this.ensureStarted();
      const response = await this.module().query(this.socket, schema, source, params);
      if (!response.available) this.ready = false;
      return response;
    });
    this.queue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  executeScript(schema: string, source: string): Promise<QfliMysqlScriptResponse> {
    if (this.closing) return Promise.reject(new Error('Oracle MySQL is closing.'));
    const operation = this.queue.then(async (): Promise<QfliMysqlScriptResponse> => {
      await this.ensureStarted();
      const response = await this.module().executeScript(this.socket, schema, source);
      if (!response.available) this.ready = false;
      return response;
    });
    this.queue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  async stop(): Promise<void> {
    this.closing = true;
    if (!this.ready && this.pid !== undefined && this.module().isChildRunning(this.pid)) {
      this.module().terminateChild(this.pid);
    }
    await this.queue;
    if (this.starting !== undefined) {
      try {
        await this.starting;
      } catch (_) {}
    }
    if (this.pid === undefined) return;
    const exitFile = this.processExit ?? `${this.root}/server.exit`;
    if (!this.module().isChildRunning(this.pid)) {
      this.pid = undefined;
      this.ready = false;
      return;
    }
    if (this.readExit(exitFile) !== undefined) {
      this.pid = undefined;
      this.ready = false;
      return;
    }
    const response = await this.module().shutdown(this.socket);
    if (!response.available || response.exitCode !== 0) {
      this.module().terminateChild(this.pid);
    }
    const exitCode = await this.waitExit(exitFile, 30000);
    this.pid = undefined;
    this.ready = false;
    if (exitCode !== 0) throw new Error(this.diagnostic('Oracle MySQL shutdown', exitCode));
  }

  private module(): QfliMysqlModule {
    if (deviceInfo.deviceType !== '2in1' && deviceInfo.deviceType !== 'tablet') {
      throw new Error('当前设备不支持应用启动原生子进程，无法运行本地 Oracle MySQL。');
    }
    if (nativeModule === undefined) throw new Error('Oracle MySQL native module is unavailable.');
    if (nativeModule.version().length === 0) {
      throw new Error('本地 Oracle MySQL 需要 HarmonyOS arm64 设备。');
    }
    return nativeModule;
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
    this.makeDirectory(this.root);
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
        this.pid = await this.startChild(true, initializeExit);
        const exitCode = await this.waitExit(initializeExit, 120000);
        this.pid = undefined;
        if (exitCode !== 0) throw new Error(this.diagnostic('Oracle MySQL initialization', exitCode));
      }
      const marker: MysqlMarker = { version: MYSQL_VERSION };
      this.writeText(markerPath, JSON.stringify(marker));
    }

    if (this.closing) throw new Error('Oracle MySQL is closing.');
    this.removeIfExists(`${this.root}/server.exit`);
    const existing = await this.module().query(this.socket, '', 'SELECT VERSION()', []);
    if (this.isReady(existing)) {
      this.pid = this.readExit(`${this.root}/mysql.pid`);
      if (this.pid === undefined || this.pid <= 1) {
        throw new Error('Oracle MySQL is reachable but its process identifier is missing.');
      }
      this.ready = true;
      this.processExit = `${this.root}/server.exit`;
      return;
    }
    if (this.pid !== undefined && this.module().isChildRunning(this.pid)) {
      this.module().terminateChild(this.pid);
      await this.waitExit(this.processExit ?? `${this.root}/server.exit`, 30000);
      this.pid = undefined;
      this.removeIfExists(`${this.root}/server.exit`);
    }
    this.pid = await this.startChild(false, `${this.root}/server.exit`);
    const deadline = Date.now() + 120000;
    while (Date.now() < deadline) {
      const exitCode = this.readExit(`${this.root}/server.exit`);
      if (exitCode !== undefined) {
        this.pid = undefined;
        throw new Error(this.diagnostic('Oracle MySQL startup', exitCode));
      }
      if (this.closing) {
        if (this.pid !== undefined) this.module().terminateChild(this.pid);
        throw new Error('Oracle MySQL is closing.');
      }
      if (this.pid !== undefined && !this.module().isChildRunning(this.pid)) {
        this.pid = undefined;
        throw new Error(this.diagnostic('Oracle MySQL exited without a startup result', undefined));
      }
      const response = await this.module().query(this.socket, '', 'SELECT VERSION()', []);
      if (this.isReady(response)) {
        this.ready = true;
        return;
      }
      await this.delay(250);
    }
    if (this.pid !== undefined) this.module().terminateChild(this.pid);
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

  private async startChild(initialize: boolean, exitFile: string): Promise<number> {
    if (this.closing) throw new Error('Oracle MySQL is closing.');
    const payload: MysqlChildPayload = {
      arguments: ['mysqld', `--defaults-file=${this.root}/my.cnf`],
      exitFile: exitFile,
      icuDataDirectory: `${this.root}/share/icu`,
    };
    if (initialize) payload.arguments.push('--initialize-insecure');
    this.processExit = exitFile;
    return childProcessManager.startNativeChildProcess(MYSQL_ENTRY,
      { entryParams: JSON.stringify(payload) });
  }

  private async waitExit(path: string, timeout: number): Promise<number> {
    const deadline = Date.now() + timeout;
    while (Date.now() < deadline) {
      const code = this.readExit(path);
      if (code !== undefined) return code;
      if (this.pid !== undefined && !this.module().isChildRunning(this.pid)) {
        this.pid = undefined;
        throw new Error(this.diagnostic('Oracle MySQL exited without an exit result', undefined));
      }
      await this.delay(100);
    }
    if (this.pid !== undefined) this.module().terminateChild(this.pid);
    throw new Error(this.diagnostic('Oracle MySQL process timed out', undefined));
  }

  private readExit(path: string): number | undefined {
    if (!fs.accessSync(path)) return undefined;
    const text = fs.readTextSync(path).trim();
    if (!/^-?\d+$/.test(text)) throw new Error(`Invalid MySQL process status: ${path}`);
    return Number(text);
  }

  private diagnostic(action: string, code: number | undefined): string {
    const logPath = `${this.root}/mysql.log`;
    let details = '';
    if (fs.accessSync(logPath)) {
      const size = fs.statSync(logPath).size;
      details = fs.readTextSync(logPath, { offset: Math.max(0, size - 8192), length: 8192 });
    }
    return `${action}${code === undefined ? '' : ` (exit ${code})`}.\n${details}`;
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
      'skip-networking',
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
