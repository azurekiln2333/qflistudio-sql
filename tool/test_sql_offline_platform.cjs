#!/usr/bin/env node
'use strict';

// Execute the actual EntryAbility with explicit SDK/native-interface doubles.
// This host regression does not replace ArkTS checking or installed OHOS tests.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
let entryPath = path.join(root, 'ohos/entry/src/main/ets/entryability/EntryAbility.ets');
let workspaceStartup = false;
for (let index = 2; index < process.argv.length; index++) {
  const option = process.argv[index];
  if (option === '--entry' && process.argv[index + 1]) {
    entryPath = path.resolve(process.argv[++index]);
  } else if (option === '--workspace-startup') {
    workspaceStartup = true;
  } else {
    throw new Error(`Unknown or incomplete argument: ${option}`);
  }
}

let assertionCount = 0;
const check = {
  equal(actual, expected, message) {
    assertionCount++;
    assert.equal(actual, expected, message);
  },
  deepEqual(actual, expected, message) {
    assertionCount++;
    assert.deepEqual(actual, expected, message);
  },
  ok(value, message) {
    assertionCount++;
    assert.ok(value, message);
  },
};

function sdkCompiler() {
  const propertiesPath = path.join(root, 'ohos/local.properties');
  const properties = fs.existsSync(propertiesPath)
    ? fs.readFileSync(propertiesPath, 'utf8') : '';
  const configuredSdks = [...properties.matchAll(/^(?:hwsdk|sdk)\.dir\s*=\s*(.+)$/gm)]
    .map(match => match[1].trim().replace(/\\([\\: ])/g, '$1'));
  const sdkHomes = [process.env.DEVECO_SDK_HOME, process.env.OHOS_SDK_HOME,
    ...configuredSdks].filter(Boolean);
  const suffix = 'openharmony/ets/build-tools/ets-loader/node_modules/typescript';
  const candidates = [process.env.QFLI_ARKTS_TYPESCRIPT,
    process.env.OHOS_ETS_LOADER && path.join(process.env.OHOS_ETS_LOADER, 'node_modules/typescript'),
    ...sdkHomes.flatMap(sdk => [path.join(sdk, 'default', suffix), path.join(sdk, suffix)])]
    .filter(Boolean);
  const compilerPath = candidates.find(candidate => fs.existsSync(path.join(candidate, 'package.json')));
  check.ok(compilerPath,
    'Use installed SDK TypeScript via local.properties, SDK env, or QFLI_ARKTS_TYPESCRIPT; no downloads');
  return require(path.resolve(compilerPath));
}

const ts = sdkCompiler();
const source = fs.readFileSync(entryPath, 'utf8');
const compiled = ts.transpileModule(source, {
  fileName: entryPath.replace(/\.ets$/, '.ts'),
  reportDiagnostics: true,
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
});
const compileErrors = (compiled.diagnostics || [])
  .filter(diagnostic => diagnostic.category === ts.DiagnosticCategory.Error)
  .map(diagnostic => ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n'));
check.deepEqual(compileErrors, [], 'Actual EntryAbility must transpile without syntax errors');

const pickerMethods = ['pickDocument', 'saveDocument', 'pickPhotos', 'readUri', 'readSqlUri', 'writeUri'];

function createHarness() {
  const channels = new Map();
  const observations = {
    external: [], registrations: [], lifecycle: [], shares: [], pickers: [],
    backgrounds: [], progress: [], errors: [], disposeCount: 0,
  };
  let rejectShare = false;
  let settleDisposal;
  const mysqlRuntime = {
    dispose() {
      observations.disposeCount++;
      observations.lifecycle.push('dispose');
      return new Promise((resolve, reject) => { settleDisposal = { resolve, reject }; });
    },
  };
  const forbidden = name => {
    observations.external.push(name);
    throw new Error(`Unexpected external platform effect: ${name}`);
  };
  const abilityContext = {
    config: { colorMode: 1 },
    startAbility: () => forbidden('startAbility'),
    eventHub: { emit: (...values) => observations.progress.push(values) },
  };
  const messenger = {};
  const engine = { dartExecutor: { getBinaryMessenger: () => messenger } };
  class FlutterAbility {
    constructor() { this.context = abilityContext; }
    configureFlutterEngine(receivedEngine) {
      check.equal(receivedEngine, engine);
      observations.lifecycle.push('configure');
    }
    onWindowStageCreate(stage) {
      observations.lifecycle.push(['window', stage]);
    }
    onDestroy() { observations.lifecycle.push('destroy'); }
  }
  class MethodChannel {
    constructor(receivedMessenger, name) {
      check.equal(receivedMessenger, messenger);
      check.equal(channels.has(name), false, `Duplicate channel ${name}`);
      this.name = name;
      channels.set(name, this);
    }
    setMethodCallHandler(handler) { this.handler = handler; }
  }
  const imports = {
    '@ohos/flutter_ohos': { FlutterAbility, MethodChannel },
    '@kit.ShareKit': { systemShare: {
      SharedData: class { constructor(record) { this.record = record; } },
      ShareController: class {
        constructor(data) { this.data = data; }
        show(receivedContext, options) {
          check.equal(receivedContext, abilityContext);
          check.deepEqual(Object.keys(options), []);
          observations.shares.push(this.data.record);
          return rejectShare ? Promise.reject({ code: 73, message: 'share denied' }) : Promise.resolve();
        }
      },
    } },
    '@kit.AbilityKit': { ConfigurationConstant: { ColorMode: { COLOR_MODE_DARK: 1 } } },
    '@kit.ArkUI': {
      get router() { return forbidden('router'); },
    },
    '@kit.BasicServicesKit': {},
    '../plugins/GeneratedPluginRegistrant': {
      GeneratedPluginRegistrant: { registerWith: receivedEngine => {
        observations.registrations.push(['generated', receivedEngine]);
      } },
    },
    '../plugins/QfliSqlNative': { registerQfliSqlNativeChannel: receivedEngine => {
      observations.registrations.push(['sqlite', receivedEngine]);
    } },
    '../plugins/QfliMysqlNative': { registerQfliMysqlChannel: (receivedEngine, receivedContext) => {
      observations.registrations.push(['mysql', receivedEngine, receivedContext]);
      return mysqlRuntime;
    } },
    '../plugins/QfliMysqlRuntime': { QfliMysqlRuntime: class {} },
    './PickerBridge': {
      isPickerMethod: method => pickerMethods.includes(method),
      handlePickerCall(receivedContext, call, result) {
        observations.pickers.push({ context: receivedContext, call, result });
        result.success(`local:${call.method}`);
      },
    },
  };
  // Type-only imports can disappear during transpilation. Inspect all declared
  // modules too, so a newly added dependency is never silently accepted.
  const parsed = ts.createSourceFile('EntryAbility.ts', source, ts.ScriptTarget.ES2020, true);
  for (const statement of parsed.statements) {
    if (ts.isImportDeclaration(statement)) {
      check.ok(Object.hasOwn(imports, statement.moduleSpecifier.text),
        `Unexpected EntryAbility import: ${statement.moduleSpecifier.text}`);
    }
  }
  const module = { exports: {} };
  vm.runInNewContext(compiled.outputText, {
    exports: module.exports,
    module,
    require: name => {
      check.ok(Object.hasOwn(imports, name), `Unexpected runtime import: ${name}`);
      return imports[name];
    },
    console: { error: (...values) => observations.errors.push(values) },
  }, { filename: entryPath });
  const ability = new module.exports.default();
  ability.configureFlutterEngine(engine);
  check.deepEqual(observations.registrations.map(registration => registration[0]),
    ['generated', 'sqlite', 'mysql'], 'Each actual native registration must run exactly once');
  for (const registration of observations.registrations) check.equal(registration[1], engine);
  check.equal(observations.registrations[2][2], abilityContext, 'MySQL must receive the ability context');
  check.deepEqual([...channels.keys()].sort(), ['qflistudio/huawei_account', 'qflistudio/platform']);
  check.deepEqual(observations.external, [], 'Engine setup must not start external services');

  async function invoke(channelName, method, args = {}, poisonArguments = false) {
    const responses = [];
    const call = { method };
    let argumentReads = 0;
    Object.defineProperty(call, 'argument', {
      get() {
        if (poisonArguments) throw new Error(`${method} must not access call.argument`);
        return key => { argumentReads++; return args[key]; };
      },
    });
    const result = {
      success: value => responses.push({ kind: 'success', value }),
      error: (code, message, details) => responses.push({ kind: 'error', code, message, details }),
      notImplemented: () => responses.push({ kind: 'notImplemented' }),
    };
    const handler = channels.get(channelName)?.handler;
    check.ok(handler, `${channelName} must have a registered handler`);
    handler.onMethodCall(call, result);
    // Flush promise-based ShareKit completions before checking exact-once replies.
    await new Promise(resolve => setImmediate(resolve));
    check.equal(responses.length, 1, `${method} must complete exactly once`);
    return { response: responses[0], argumentReads, call, result };
  }
  return {
    ability, abilityContext, observations, invoke,
    setShareFailure: value => { rejectShare = value; },
    settleDisposal: failure => {
      check.ok(settleDisposal, 'onDestroy must invoke the owned runtime disposal');
      failure ? settleDisposal.reject(new Error('dispose denied')) : settleDisposal.resolve();
    },
  };
}

async function verifyDisposal(harness, fails) {
  const { ability, observations } = harness;
  const destruction = ability.onDestroy();
  check.equal(observations.disposeCount, 1);
  check.equal(observations.lifecycle.includes('destroy'), false,
    'Superclass destruction must wait for the owned MySQL runtime');
  harness.settleDisposal(fails);
  await destruction;
  check.equal(observations.lifecycle.filter(event => event === 'destroy').length, 1);
  check.equal(observations.errors.length, fails ? 1 : 0);
  if (fails) check.ok(String(observations.errors[0][0]).includes('dispose denied'));
}

async function main() {
  const harness = createHarness();
  const { ability, abilityContext, observations, invoke } = harness;
  const platform = 'qflistudio/platform';
  const account = 'qflistudio/huawei_account';
  let refused = 0;
  async function refuse(channel, method, args = {}, poison = false) {
    const { response, argumentReads } = await invoke(channel, method, args, poison);
    check.equal(response.kind, 'error');
    check.equal(response.code, 'OFFLINE_ONLY');
    check.ok(typeof response.message === 'string' && response.message.length > 0);
    check.equal(response.details, null);
    check.equal(argumentReads, 0, `${method} must refuse before reading any argument`);
    refused++;
  }
  for (const method of ['openAgreement', 'openUrl']) {
    for (const url of [undefined, null, '', 'https://example.invalid/privacy',
      'http://example.invalid/', 'http://127.0.0.1:8080/', '//example.invalid/',
      'file:///data/local/tmp/local.html', 'custom://action']) {
      await refuse(platform, method, { url, title: 'Agreement' });
    }
    await refuse(platform, method, {}, true);
  }
  await refuse(account, 'login', { authorizationCode: 'stale-token' });
  await refuse(account, 'login', {}, true);
  check.deepEqual(observations.external, [], 'Refusals must cause zero browser/router/auth effects');

  let invocation = await invoke(platform, 'shareText', { title: 'SQL 草稿', text: 'SELECT 1;\n' });
  check.equal(invocation.response.kind, 'success');
  check.equal(invocation.response.value, null);
  check.equal(invocation.argumentReads, 2);
  check.equal(observations.shares.length, 1);
  check.equal(observations.shares[0].utd, 'general.plain-text');
  check.equal(observations.shares[0].title, 'SQL 草稿');
  check.equal(observations.shares[0].content, 'SELECT 1;\n');
  harness.setShareFailure(true);
  invocation = await invoke(platform, 'shareText', { title: 'SQL', text: 'SELECT 2;' });
  check.equal(invocation.response.code, 'SHARE_FAILED');
  check.equal(invocation.response.message, '73: share denied');
  check.equal(invocation.response.details, null);
  check.equal(observations.shares.length, 2);

  for (const method of pickerMethods) {
    invocation = await invoke(platform, method);
    const dispatch = observations.pickers.at(-1);
    check.equal(invocation.response.kind, 'success');
    check.equal(invocation.response.value, `local:${method}`);
    check.equal(dispatch.context, abilityContext);
    check.equal(dispatch.call, invocation.call, 'Picker must receive the original call');
    check.equal(dispatch.result, invocation.result, 'Picker must receive the original result');
  }
  check.equal(observations.pickers.length, pickerMethods.length);
  for (const channel of [platform, account]) {
    invocation = await invoke(channel, 'unknown', {}, true);
    check.equal(invocation.response.kind, 'notImplemented');
  }

  for (const [colorMode, background] of [[1, '#FF111418'], [0, '#FFF8F9FF']]) {
    abilityContext.config.colorMode = colorMode;
    const stage = { getMainWindowSync: () => ({
      setWindowBackgroundColor: color => observations.backgrounds.push(color),
    }) };
    ability.onWindowStageCreate(stage);
    check.equal(observations.backgrounds.at(-1), background);
    check.equal(observations.lifecycle.at(-1)[0], 'window');
    check.equal(observations.lifecycle.at(-1)[1], stage);
  }
  const failedWindow = { getMainWindowSync: () => { throw new Error('window unavailable'); } };
  ability.onWindowStageCreate(failedWindow);
  check.equal(observations.lifecycle.at(-1)[1], failedWindow,
    'Window customization failure must still call the superclass');

  if (workspaceStartup) {
    for (const [progress, expected] of [[-0.5, 0], [0.25, 0.25], [1.5, 1]]) {
      invocation = await invoke(platform, 'startupProgress', { progress });
      check.equal(invocation.response.kind, 'success');
      check.equal(invocation.response.value, null);
      check.deepEqual(observations.progress.at(-1), ['EVENT_STARTUP_PROGRESS', expected]);
    }
    for (const progress of [undefined, null, '0.5', NaN, Infinity, -Infinity]) {
      invocation = await invoke(platform, 'startupProgress', { progress });
      check.equal(invocation.response.code, 'INVALID_PROGRESS');
    }
    check.equal(observations.progress.length, 3, 'Invalid startup progress must not emit events');
  }
  await verifyDisposal(harness, false);
  const failureHarness = createHarness();
  await verifyDisposal(failureHarness, true);
  check.deepEqual(observations.external, []);
  check.deepEqual(failureHarness.observations.external, []);
  console.log(`PASS SQL EntryAbility: ${assertionCount} assertions; ${refused} offline refusals; ` +
    '6 picker routes; share success/failure; disposal success/failure; window preservation' +
    (workspaceStartup ? '; startup progress 9 cases' : ''));
  console.log(`Source SHA256: ${crypto.createHash('sha256').update(source).digest('hex')}`);
  console.log('Coverage: SDK TypeScript transpile and explicit interface doubles; ' +
    'no ArkTS type check, actual picker/share IO, installed OHOS run or network trace.');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
