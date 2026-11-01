import { common } from '@kit.AbilityKit';
import { FlutterEngine, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
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
      } else if (call.method === 'stop') {
        runtime.stop().then(() => { result.success(null); })
          .catch((error: Error) => { result.error('MYSQL_SHUTDOWN_FAILED', error.message, null); });
      } else {
        result.notImplemented();
      }
    },
  });
  return runtime;
}
