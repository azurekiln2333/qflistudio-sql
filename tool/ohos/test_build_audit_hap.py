"""Actual build-wrapper controls with a private fake SDK and no real build."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
NODE = shutil.which('node.exe')
TOOL_FILES = {
    'node': 'tools/node/node.exe',
    'npm': 'tools/node/npm.cmd',
    'npmCli': 'tools/node/node_modules/npm/bin/npm-cli.js',
    'npmPrefix': 'tools/node/node_modules/npm/bin/npm-prefix.js',
    'ohpm': 'tools/ohpm/bin/ohpm.bat',
    'ohpmCli': 'tools/ohpm/bin/pm-cli.js',
    'hvigor': 'tools/hvigor/bin/hvigorw.bat',
    'hvigorCli': 'tools/hvigor/bin/hvigorw.js',
    'java': 'jbr/bin/java.exe',
    'sdkPackage': 'sdk/default/sdk-pkg.json',
}
ENVIRONMENT_KEYS = (
    'NODE_HOME', 'JAVA_HOME', 'DEVECO_SDK_HOME', 'HOS_SDK_HOME',
    'npm_config_prefix', 'OHOS_HOME', 'OHOS_SDK_HOME', 'PATH',
)


def create_toolchain_fixture(fixture, *, node=None):
    """Inert by default, including Node; early-read tests must never invoke it."""
    dev_eco = fixture / 'selected DevEco'
    for relative in TOOL_FILES.values():
        path = dev_eco / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(('inert fixture: ' + relative + '\n').encode())
    (dev_eco / 'sdk/default/openharmony/toolchains').mkdir(parents=True)
    if node:
        shutil.copy2(node, dev_eco / TOOL_FILES['node'])
    return dev_eco


def fixture_environment(fixture):
    environment = dict(os.environ)
    app_data = fixture / 'private-appdata'
    app_data.mkdir()
    environment['APPDATA'] = str(app_data)
    return environment


@unittest.skipUnless(os.name == 'nt' and shutil.which('pwsh'),
                     'Windows PowerShell is required for batch wrapper controls')
class AuditBuildToolchainTest(unittest.TestCase):
    def prepare(self, fixture, *, real_node=False):
        (fixture / 'tool/ohos').mkdir(parents=True)
        (fixture / 'ohos/AppScope').mkdir(parents=True)
        script = fixture / 'tool/ohos/build_audit_hap.ps1'
        shutil.copy2(ROOT / 'tool/ohos/build_audit_hap.ps1', script)
        (fixture / 'target.dart').write_text('void main() {}\n', encoding='utf-8')
        dev_eco = create_toolchain_fixture(fixture, node=NODE if real_node else None)
        parser = fixture / 'json5-control.cjs'
        parser.write_text(
            "const fs = require('fs');\n"
            "if (process.env.QFLI_METADATA_PROBE) fs.writeFileSync(process.env.QFLI_METADATA_PROBE, "
            "JSON.stringify({execPath: process.execPath}));\n"
            'exports.parse = JSON.parse;\n', encoding='utf-8')
        flutter = fixture / 'explicit-flutter-control.cmd'
        flutter.write_bytes(
            b'@echo QFLI_EXPLICIT_FLUTTER_CONTROL\r\n'
            b'@"%NODE_HOME%\\node.exe" "%~dp0flutter-probe.cjs"\r\n'
            b'@if errorlevel 1 exit /b %errorlevel%\r\n'
            b'@exit /b %QFLI_FAKE_FLUTTER_EXIT%\r\n')
        (fixture / 'flutter-probe.cjs').write_text(
            "const fs = require('fs'), path = require('path');\n"
            f'const keys = {json.dumps(ENVIRONMENT_KEYS)};\n'
            'fs.writeFileSync(process.env.QFLI_FLUTTER_PROBE, JSON.stringify({\n'
            '  execPath: process.execPath,\n'
            '  environment: Object.fromEntries(keys.map(k => [k, process.env[k] ?? null]))\n'
            '}));\n'
            "if (process.env.QFLI_FAKE_FLUTTER_EXIT === '0') {\n"
            "  const hap = path.join(process.cwd(), 'ohos/entry/build/default/outputs/default/entry-default-unsigned.hap');\n"
            '  fs.mkdirSync(path.dirname(hap), {recursive: true});\n'
            "  fs.writeFileSync(hap, 'QFLI_FAKE_HAP_FIXTURE_ONLY\\n');\n"
            '}\n'
            "if (process.env.QFLI_FAKE_TOOL_DRIFT === '1') {\n"
            "  fs.appendFileSync(path.join(process.env.NODE_HOME, 'node_modules/npm/bin/npm-cli.js'), '// changed by fake build\\n');\n"
            '}\n', encoding='utf-8')
        caller = fixture / 'caller'
        caller.mkdir()
        profile = fixture / 'ohos/build-profile.json5'
        app = fixture / 'ohos/AppScope/app.json5'
        profile.write_text(json.dumps({'app': {
            'signingConfigs': [{'name': 'fixture', 'fixtureMarker': 'preserve'}],
            'products': [{'name': 'default', 'signingConfig': 'fixture'}],
        }}), encoding='utf-8')
        app.write_text('{"app":{"bundleName":"fixture.original"}}\n', encoding='utf-8')
        return script, dev_eco, parser, flutter, caller, (profile, app)

    @unittest.skipUnless(NODE, 'A real standalone Node executable is needed for metadata controls')
    def test_selected_toolchain_and_environment_restore_on_build_success_and_failure(self):
        for exit_code, tool_drift in ((0, False), (17, False), (0, True)):
            with self.subTest(exit_code=exit_code, tool_drift=tool_drift), tempfile.TemporaryDirectory(prefix='qfli-build-control-') as directory:
                fixture = Path(directory)
                script, dev_eco, parser, flutter, caller, metadata = self.prepare(fixture, real_node=True)
                originals = {path: path.read_bytes() for path in metadata}
                environment = fixture_environment(fixture)
                if not exit_code:
                    # Flutter resolves this selector after entering the repo,
                    # while the wrapper itself is invoked from caller/.
                    (Path(environment['APPDATA']) / '.flutter_settings').write_text(
                        json.dumps({'ohos-sdk': 'selected DevEco/sdk'}), encoding='utf-8')
                poison = fixture / 'ambient-poison'
                poison.mkdir()
                (poison / 'node.cmd').write_bytes(b'@echo AMBIENT_NODE_MUST_NOT_RUN\r\n@exit /b 93\r\n')
                for name in ENVIRONMENT_KEYS:
                    if name != 'PATH':
                        environment[name] = 'QFLI_ORIGINAL_' + name
                if exit_code:
                    environment.pop('JAVA_HOME', None)
                environment['PATH'] = str(poison) + os.pathsep + environment.get('PATH', '')
                environment['QFLI_FAKE_FLUTTER_EXIT'] = str(exit_code)
                environment['QFLI_FAKE_TOOL_DRIFT'] = '1' if tool_drift else '0'
                for label in ('METADATA', 'FLUTTER', 'RESTORE'):
                    environment['QFLI_' + label + '_PROBE'] = str(fixture / (label.lower() + '-probe.json'))
                harness = fixture / 'invoke-and-observe.ps1'
                harness.write_text(
                    'param([string]$Builder, [string]$Flutter, [string]$DevEcoHome, [string]$Json5Module)\n'
                    "$ErrorActionPreference = 'Stop'\n"
                    '$taskKeys = ' + '@(' + ','.join("'" + key + "'" for key in ENVIRONMENT_KEYS) + ')\n'
                    '$taskBefore = @{}\n'
                    "foreach ($key in $taskKeys) { $taskBefore[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }\n"
                    '$global:LASTEXITCODE = 91\n$taskFailure = $null\n'
                    "try { & $Builder -Target 'target.dart' -Flutter $Flutter -DevEcoHome $DevEcoHome -Json5Module $Json5Module }\n"
                    'catch { $taskFailure = $_.Exception.Message }\n'
                    '$taskAfter = @{}\n'
                    "foreach ($key in $taskKeys) { $taskAfter[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }\n"
                    '[IO.File]::WriteAllText($env:QFLI_RESTORE_PROBE, '
                    '(@{before=$taskBefore; after=$taskAfter; failure=$taskFailure} | ConvertTo-Json -Depth 4))\n'
                    'if ($taskFailure) { [Console]::Error.WriteLine($taskFailure); exit 1 }\nexit 0\n',
                    encoding='utf-8')
                result = subprocess.run(
                    [shutil.which('pwsh'), '-NoProfile', '-File', str(harness), '-Builder', str(script),
                     '-Flutter', os.path.relpath(flutter, caller),
                     '-DevEcoHome', os.path.relpath(dev_eco, caller),
                     '-Json5Module', os.path.relpath(parser, caller)],
                    cwd=caller, env=environment,
                    capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=30,
                )
                restored = json.loads((fixture / 'restore-probe.json').read_text(encoding='utf-8-sig'))
                self.assertEqual(restored['after'], restored['before'])
                for path, original in originals.items():
                    self.assertEqual(path.read_bytes(), original)
                output = fixture / 'build/ohos-audit'
                self.assertFalse((output / '.build-lock').exists())
                self.assertIn('QFLI_EXPLICIT_FLUTTER_CONTROL', (output / 'build.log').read_text(encoding='utf-8-sig'))
                selected_node = (dev_eco / TOOL_FILES['node']).resolve()
                self.assertEqual(Path(json.loads((fixture / 'metadata-probe.json').read_text())['execPath']), selected_node)
                probe = json.loads((fixture / 'flutter-probe.json').read_text())
                self.assertEqual(Path(probe['execPath']), selected_node)
                expected_environment = {
                    'NODE_HOME': str(dev_eco / 'tools/node'), 'JAVA_HOME': str(dev_eco / 'jbr'),
                    'DEVECO_SDK_HOME': str(dev_eco / 'sdk'), 'HOS_SDK_HOME': str(dev_eco / 'sdk'),
                    'npm_config_prefix': str(dev_eco / 'tools/node'), 'OHOS_HOME': None, 'OHOS_SDK_HOME': None,
                }
                for name, value in expected_environment.items():
                    self.assertEqual(probe['environment'][name], value, name)
                prefix = [str(dev_eco / relative) for relative in (
                    'tools/node', 'tools/ohpm/bin', 'tools/hvigor/bin', 'jbr/bin',
                    'sdk/default/openharmony/toolchains')]
                self.assertEqual(probe['environment']['PATH'].split(os.pathsep)[:len(prefix)], prefix)
                self.assertNotIn('AMBIENT_NODE_MUST_NOT_RUN', result.stdout + result.stderr)
                if exit_code or tool_drift:
                    self.assertNotEqual(result.returncode, 0)
                    diagnostic = 'Selected toolchain input changed during the build: npmCli' if tool_drift else 'Audit build failed'
                    self.assertIn(diagnostic, restored['failure'])
                    for name in ('build.json', 'sql-audit-unsigned.hap'):
                        self.assertFalse((output / name).exists(), name)
                else:
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIsNone(restored['failure'])
                    self.assertEqual((output / 'sql-audit-unsigned.hap').read_bytes(), b'QFLI_FAKE_HAP_FIXTURE_ONLY\n')
                    record = json.loads((output / 'build.json').read_text(encoding='utf-8-sig'))
                    self.assertIs(record['signed'], False)
                    self.assertIs(record['deviceExecuted'], False)
                    toolchain = record['toolchain']
                    self.assertEqual(Path(toolchain['devEcoHome']), dev_eco.resolve())
                    self.assertEqual(Path(toolchain['sdkRoot']), (dev_eco / 'sdk').resolve())
                    expected_inputs = {key: dev_eco / relative for key, relative in TOOL_FILES.items()}
                    expected_inputs.update(flutter=flutter, json5=parser)
                    self.assertEqual(set(toolchain['inputs']), set(expected_inputs))
                    for key, path in expected_inputs.items():
                        self.assertEqual(Path(toolchain['inputs'][key]['path']), path.resolve())
                        self.assertEqual(toolchain['inputs'][key]['sha256'].lower(), hashlib.sha256(path.read_bytes()).hexdigest())

    def test_toolchain_preflight_rejects_missing_input_settings_conflict_and_local_wrapper(self):
        for problem in ('missing-input', 'sdk-conflict', 'sdk-conflict-unset-appdata',
                        'sdk-conflict-relative-appdata', 'local-wrapper'):
            with self.subTest(problem=problem), tempfile.TemporaryDirectory(prefix='qfli-build-preflight-') as directory:
                fixture = Path(directory)
                script, dev_eco, parser, flutter, caller, metadata = self.prepare(fixture)
                originals = {path: path.read_bytes() for path in metadata}
                environment = fixture_environment(fixture)
                if problem == 'missing-input':
                    (dev_eco / TOOL_FILES['npmCli']).unlink()
                    diagnostic = 'Selected toolchain input does not exist: npmCli'
                elif problem.startswith('sdk-conflict'):
                    other_sdk = fixture / 'different-sdk'
                    other_sdk.mkdir()
                    settings_home = Path(environment['APPDATA'])
                    if problem == 'sdk-conflict-unset-appdata':
                        environment.pop('APPDATA')
                        settings_home = fixture
                    elif problem == 'sdk-conflict-relative-appdata':
                        environment['APPDATA'] = settings_home.name
                    (settings_home / '.flutter_settings').write_text(
                        json.dumps({'ohos-sdk': str(other_sdk), 'unrelated-private-setting': 'DO_NOT_PRINT'}), encoding='utf-8')
                    diagnostic = 'Persistent ohos-sdk conflicts'
                else:
                    (fixture / 'ohos/hvigorw.bat').write_text('exit /b 94\n', encoding='utf-8')
                    diagnostic = 'Unbound project-local Hvigor wrapper'
                result = subprocess.run(
                    [shutil.which('pwsh'), '-NoProfile', '-File', str(script), '-Target', 'target.dart',
                     '-Flutter', str(flutter), '-DevEcoHome', str(dev_eco), '-Json5Module', str(parser)],
                    cwd=caller, env=environment,
                    capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=30,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(diagnostic, result.stdout + result.stderr)
                self.assertNotIn('DO_NOT_PRINT', result.stdout + result.stderr)
                self.assertFalse((fixture / 'build/ohos-audit').exists(), 'Preflight must precede lock/output creation')
                for path, original in originals.items():
                    self.assertEqual(path.read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
