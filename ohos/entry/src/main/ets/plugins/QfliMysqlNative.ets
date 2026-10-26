import { common } from '@kit.AbilityKit';
import { FlutterEngine, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import BuildProfile from 'BuildProfile';
import { QfliMysqlRuntime } from './QfliMysqlRuntime';

export function registerQfliMysqlChannel(engine: FlutterEngine,
  context: common.UIAbilityContext): QfliMysqlRuntime {
  const runtime = new QfliMysqlRuntime(context);
  const channel = new MethodChannel(engine.dartExecutor.getBinaryMessenger(), 'qfli_sql/mysql');
  channel.setMethodCallHandler({
    onMethodCall(call: MethodCall, result: MethodResult): void {
      if (call.method === 'query') {
        runtime.query(call.argument('schema') as string,
          call.argument('source') as string,
          call.argument('params') as Array<string | null>)
          .then((response) => { result.success(response); })
          .catch((error: Error) => { result.error('MYSQL_QUERY_FAILED', error.message, null); });
      } else if (call.method === 'executeScript') {
        runtime.executeScript(call.argument('schema') as string,
          call.argument('source') as string)
          .then((response) => { result.success(response); })
          .catch((error: Error) => { result.error('MYSQL_SCRIPT_FAILED', error.message, null); });
      } else if (call.method === 'sharingStatus') {
        runtime.sharingStatus().then((response) => { result.success(response); })
          .catch(() => { result.error('MYSQL_SHARING_STATUS_FAILED', 'Could not inspect MySQL sharing.', null); });
      } else if (call.method === 'startSharing') {
        runtime.startSharing().then((response) => { result.success(response); })
          .catch(() => { result.error('MYSQL_SHARING_START_FAILED', 'Could not start MySQL sharing.', null); });
      } else if (call.method === 'stopSharing') {
        runtime.stopSharing().then((response) => { result.success(response); })
          .catch(() => { result.error('MYSQL_SHARING_STOP_FAILED', 'Could not stop MySQL sharing.', null); });
      } else if (call.method === 'stop') {
        runtime.stop().then(() => { result.success(null); })
          .catch((error: Error) => { result.error('MYSQL_SHUTDOWN_FAILED', error.message, null); });
      } else if (call.method === 'configureProbeRoot') {
        // Debug/test-only isolated root for the OHOS integration probe. Refused
        // in release builds so production cannot be pointed at a probe path.
        if (!BuildProfile.DEBUG) {
          result.error('MYSQL_PROBE_ROOT_DISABLED', 'Probe root is debug-only.', null);
          return;
        }
        try {
          const root = runtime.configureProbeRoot(call.argument('runKey') as string);
          result.success(root);
        } catch (error) {
          result.error('MYSQL_PROBE_ROOT_FAILED', `${error}`, null);
        }
      } else if (call.method === 'runtimeRoot') {
        result.success(runtime.runtimeRoot());
      } else if (call.method === 'protoProbe') {
        // Debug-only option-B instrumentation (native prototype DSO).
        if (!BuildProfile.DEBUG) {
          result.error('MYSQL_PROTO_DISABLED', 'Prototype probe is debug-only.', null);
          return;
        }
        try {
          const probe = (runtime.protoProbeNative() as Record<string, Object>);
          result.success(probe);
        } catch (error) {
          result.error('MYSQL_PROTO_FAILED', `${error}`, null);
        }
      } else {
        result.notImplemented();
      }
    },
  });
  return runtime;
}
