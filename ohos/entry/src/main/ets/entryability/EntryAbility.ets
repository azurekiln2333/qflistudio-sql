
import {
  FlutterAbility,
  FlutterEngine,
  MethodChannel,
  MethodCall,
  MethodResult,
} from '@ohos/flutter_ohos';
import { systemShare } from '@kit.ShareKit';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { registerQfliSqlNativeChannel } from '../plugins/QfliSqlNative';
import { registerQfliMysqlChannel } from '../plugins/QfliMysqlNative';
import { QfliMysqlRuntime } from '../plugins/QfliMysqlRuntime';
import { handlePickerCall, isPickerMethod } from './PickerBridge';

const CHANNEL_PLATFORM = 'qflistudio/platform';
const CHANNEL_HUAWEI = 'qflistudio/huawei_account';

export default class EntryAbility extends FlutterAbility {
  private mysqlRuntime: QfliMysqlRuntime | undefined;

  async onDestroy(): Promise<void> {
    try {
      await this.mysqlRuntime?.dispose();
    } catch (error) {
      console.error(`Oracle MySQL shutdown: ${error}`);
    } finally {
      super.onDestroy();
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 启动遮罩消失后、Flutter 首帧渲染前，引擎初始化期间窗口会露出
    // 默认白底。窗口底色与 Flutter 的 MD3 surface 保持一致。
    try {
      const isDark = this.context.config?.colorMode ===
        ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      windowStage.getMainWindowSync().setWindowBackgroundColor(
        isDark ? '#FF111418' : '#FFF8F9FF',
      );
    } catch (e) {
      // 设置失败不影响启动（仅深色模式可能出现短暂白闪）。
    }
    super.onWindowStageCreate(windowStage);
  }

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    registerQfliSqlNativeChannel(flutterEngine)

    const abilityContext = this.context as common.UIAbilityContext;
    this.mysqlRuntime = registerQfliMysqlChannel(flutterEngine, abilityContext);

    // 通用平台能力：离线模式拒绝外链，保留本地分享和文件操作。
    const platformChannel = new MethodChannel(
      flutterEngine.dartExecutor.getBinaryMessenger(),
      CHANNEL_PLATFORM,
    );
    platformChannel.setMethodCallHandler({
      onMethodCall(call: MethodCall, result: MethodResult): void {
        if (call.method === 'openAgreement') {
          result.error('OFFLINE_ONLY', '离线模式不支持打开在线协议', null);
          return;
        } else if (call.method === 'openUrl') {
          result.error('OFFLINE_ONLY', '离线模式不支持打开外部链接', null);
          return;
        } else if (call.method === 'shareText') {
          // 系统分享面板（Share Kit）：纯文本分享。
          const title = call.argument('title') as string;
          const text = call.argument('text') as string;
          const record: systemShare.SharedRecord = {
            utd: 'general.plain-text',
            content: text,
            title: title,
          };
          const data = new systemShare.SharedData(record);
          const controller = new systemShare.ShareController(data);
          const options: systemShare.ShareControllerOptions = {};
          controller.show(abilityContext, options)
            .then(() => {
              result.success(null);
            })
            .catch((err: BusinessError) => {
              result.error('SHARE_FAILED', `${err.code}: ${err.message}`, null);
            });
        } else if (isPickerMethod(call.method)) {
          handlePickerCall(abilityContext, call, result);
        } else {
          result.notImplemented();
        }
      },
    });

    // 保留华为账号通道兼容性；离线模式不执行账号认证。
    const huaweiChannel = new MethodChannel(
      flutterEngine.dartExecutor.getBinaryMessenger(),
      CHANNEL_HUAWEI,
    );
    huaweiChannel.setMethodCallHandler({
      onMethodCall(call: MethodCall, result: MethodResult): void {
        if (call.method === 'login') {
          result.error('OFFLINE_ONLY', '离线模式不支持华为账号登录', null);
          return;
        } else {
          result.notImplemented();
        }
      },
    });
  }
}
