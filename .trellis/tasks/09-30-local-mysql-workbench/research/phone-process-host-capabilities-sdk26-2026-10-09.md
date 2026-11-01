# Research: Phone native process hosting in SDK 26

- Query: Can a normal third-party HarmonyOS phone app host a separate long-running native service through a supported Ability mechanism if direct executable startup is unavailable?
- Scope: mixed; installed SDK, official OpenHarmony documentation, current app call sites. Read-only except this research note.
- Date: 2026-10-09

## Findings

No supported general-purpose phone service alternative was established among the APIs below. This describes verified API contracts, not proof that all phone native execution is impossible.

SDK root: `D:/ProgramFiles/Huawei/DevEco Studio/sdk/default/openharmony/`. Its `ets/oh-uni-package.json` reports **API 26, release 26.0.0.105**. Parent reports MRT-AL10, OpenHarmony-7.0.0.105/HongMeng kernel, and app target API 24; no device commands were run by this researcher.

| Mechanism | Verified contract | Phone consequence |
| --- | --- | --- |
| AppServiceExtensionAbility | API 20+; only 2-in-1; SUPPORT_APP_SERVICE_EXTENSION ACL only for enterprise applications. Installed SDK and current official API reference agree. | Normal phone app does not qualify. |
| ArkTS childProcessManager start APIs | SDK 26 explicitly lists PC/2-in-1/tablet. Old API unsupported-device error 16000061; newer APIs 801. | SELF_FORK versus APP_SPAWN_FORK is not a documented phone exemption. |
| C OH_Ability_CreateNativeChildProcess / StartNativeChildProcess | Introduced API 12/13; official docs: PC/2-in-1 through API 13, additionally tablet since API 14; other devices return 801. | C does not expand documented device eligibility. |
| C WithConfigs variants | API 20+; same PC/2-in-1/tablet restriction. | Isolation, UID and name options do not grant phone support. |
| StartOptions.processMode / startupVisibility | API 12+; must be set together; only 2-in-1/tablet, 801 on other devices. | Hidden secondary UIAbility is not a documented phone service workaround. |
| module.isolationMode | Official module reference: isolated module process on 2-in-1/tablet only; HAP only. | Separate feature HAP is not sufficient. |
| module.process | Official reference: device-specific application privileges take effect, third-party app configuration does not. | Naming a process is not an ordinary third-party solution. |
| executableBinaryPaths | API 24+; PC/2-in-1 only. | Do not extrapolate to phone; parent reports installation error 9568449 separately. |

### API 26 capability checks

SDK adds `childProcessManager.isNativeChildProcessSupported()`, `isArkChildProcessSupported()`, and C `OH_Ability_IsNativeChildProcessSupported()`, all since **26.0.0**. They check whether the **caller** is allowed to create a child on the device. They query capability; they do not grant permission or themselves establish phone support.

An API-24-targeting app needs appropriate runtime API/symbol availability handling. Actual results from this installed phone would improve evidence; none were measured by this researcher. The new queries do not erase restrictions still stated on the startup APIs.

### Files found and code patterns

SDK-relative paths below use the SDK root above:

- `ets/oh-uni-package.json:2`: API/version metadata.
- `ets/api/@ohos.app.ability.AppServiceExtensionAbility.d.ts:20`: 2-in-1 and enterprise ACL constraints.
- `ets/api/@ohos.app.ability.childProcessManager.d.ts:38`: start modes; `:62`, `:127`, `:162`: device restrictions; `:190` through `:214`: API 26 eligibility checks.
- `native/sysroot/usr/include/AbilityKit/native_child_process.h:67`: unsupported error 801; `:279`, `:322`, `:412`, `:448`: creation/start signatures; `:521` through `:528`: API 26 query. C device lists come from the official reference, not just this header.
- `ets/api/@ohos.app.ability.contextConstant.d.ts:109`: process-mode device limits.
- `ets/api/@ohos.app.ability.StartOptions.d.ts:154`: processMode and startupVisibility restrictions.
- `toolchains/modulecheck/module.json:2655` and `:2843`: isolation/executable-path schemas. Schema recognition alone does not prove runtime eligibility.
- `ohos/entry/src/main/ets/plugins/QfliMysqlRuntime.ets:293`: inspected host selector uses framework children on 2in1/tablet and experimental fork elsewhere; `:433`, `:436`: start calls. Pi is actively editing this implementation.
- `native/mysql/qfli_mysql_host.cpp:216`: argument preparation and native launch; `:289` was execv at inspection. Comments about exact rejected syscalls are not independent device evidence.
- `ohos/entry/src/main/module.json5:8`: phone-only declaration.

### External references

Official `openharmony/docs` master content fetched on 2026-10-09; URLs are moving references.

1. [AppService API](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-ability-kit/js-apis-app-ability-appServiceExtensionAbility.md), Constraints, raw lines 17-20: only 2-in-1; enterprise-only ACL.
2. [Native-child C API](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-ability-kit/capi-native-child-process-h.md), raw lines 274, 311, 345, 380: Device behavior differences for all four create/start variants.
3. [ContextConstant](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-ability-kit/js-apis-app-ability-contextConstant.md#processmode12), raw lines 38-52 and 102: only 2-in-1/tablet, 801 elsewhere, same-app/status-bar constraints.
4. [Module configuration](https://github.com/openharmony/docs/blob/master/en/application-dev/quick-start/module-configuration-file.md), raw lines 131, 149, 168: process, isolationMode, executableBinaryPaths. These rows arrived completely; transport later timed out after 32768 bytes. Missing remainder was not used.
5. [Huawei AppService reference](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-ability-appserviceextensionability): only JavaScript app shell retrieved (build 20260929183102), not rendered article. Navigation reference only, not independently verified article evidence.

### Related specs

- `.trellis/workflow.md`: persist research in active task.
- `.trellis/spec/backend/mysql-workspace.md`: Oracle/native hosting, private socket, real-device acceptance; old reject-phone code description is being superseded by the active investigation.
- `research/ohos-resume-2026-10-09.md`: Pi owns implementation; parent owns device evidence; separate children, no unsafe inherited-runtime workaround.

## Caveats / Not Found

- No successful phone native-child start or live capability query was performed here.
- Official OpenHarmony docs and installed Huawei SDK agree on listed restrictions; neither is direct inspection of closed phone-kernel policy.
- Public SDK does not include `@ohos.app.ability.ServiceExtensionAbility.d.ts`; absence alone does not prove the platform has no service mechanism. Fetch of the separate system-API reference failed.
- Parent corrected earlier log lookup: UIAbilityContext.filesDir is `/data/storage/el2/base/haps/entry/files`, whereas Dart AppPaths uses `/data/storage/el2/base/files`. Absence at the latter path says nothing about prctl or launch progress.
- Latest parent evidence: trace reaches `fork -> parent-ok -> signals -> fds-closed -> exec-failed`, and execv returns **EACCES**. This does not distinguish file mode, traversal, mount, interpreter permissions or platform policy by itself.
- Parent also reports normal hdc shell cannot execute mode-0755 `/lib/ld-musl-aarch64.so.1 --help`; shell-domain evidence is not app-domain proof.
- Direct system-interpreter invocation is a separate follow-up topic; it is not asserted as a supported phone workaround in this note.
