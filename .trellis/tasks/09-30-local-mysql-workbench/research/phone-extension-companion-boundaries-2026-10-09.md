# Research: Phone extension and companion-process boundaries

- Query: Do abilities.isolationProcess, extensionAbilities.isolationProcess, extensionProcessMode, UIExtension subclasses, or a genuine companion app supply a supported process host for local MySQL on an ordinary phone app?
- Scope: mixed; installed SDK declarations, official OpenHarmony documentation, current application storage/transport contract, and parent-reported phone capability results.
- Date: 2026-10-09

## Findings

**Phone applications can have genuine extension/other-application process boundaries. No general persistent same-app MySQL host was established by the newly identified fields.** Device eligibility, a valid component scenario, how it is launched, how long it lives, and how the client talks to it are separate requirements.

The installed SDK is **API 26, version 26.0.0.105**, rooted at `D:/ProgramFiles/Huawei/DevEco Studio/sdk/default/openharmony`. Parent reports MRT-AL10, OpenHarmony-7.0.0.105 / HongMeng kernel, an ordinary debug phone app, native-child and Ark-child capability queries returning false, and both packaged-exec and system-interpreter exec failing EACCES. This researcher did not operate the device.

### 1. The two isolationProcess fields have different contracts

| Mechanism | Verified public contract | Consequence for this phone task |
| --- | --- | --- |
| `abilities[].isolationProcess` | Official module reference line 320: UIAbility process isolation is supported on 2-in-1/tablets. | Setting it does not establish ordinary phone support. |
| `abilities[].process` | Module reference line 325: named UIAbility process likewise targets PC/2-in-1/tablet use. | A process name is not an independent phone permission. |
| `extensionAbilities[].isolationProcess` | Module reference line 503: API 20+, applicable only to system-application `sys/commonUI` extensions. | Not a generic third-party ExtensionAbility isolation switch. |
| `extensionAbilities[].extensionProcessMode` | Module reference line 500: `instance`, `type`, and `bundle` placement for UIExtensionAbility subclasses. | Real process-placement control within eligible UIExtension scenarios; it does not supply a new service type or arbitrary launcher. |
| Generic UIExtensionAbility | SDK `@ohos.app.ability.UIExtensionAbility.d.ts:24-35`: cannot be inherited directly; choose a scenario-specific subclass; visibility/foreground state follow the host window. | Not a generic engine-service superclass. |
| EmbeddedUIExtensionAbility | SDK `@ohos.app.ability.EmbeddedUIExtensionAbility.d.ts:21-34`: cross-process embedded UI, only PC/2-in-1/tablets; unavailable on other devices. | The otherwise attractive same-app embedded UI route is explicitly unavailable on phone. |
| ActionExtensionAbility | SDK `@ohos.app.ability.ActionExtensionAbility.d.ts:20-38`: content viewing/processing for other applications; API 10+; deprecated since 26.0.0. | A real extension scenario, not proven unavailable merely because deprecated. No documented arbitrary private MySQL launch/lifetime follows from the declaration. |

The official stage process model (`process-model-stage.md:18-21,32-39`) explicitly describes separate ExtensionAbility processes and per-instance UIExtension processes. It also associates process lifetime with contained Ability instances and limits the special UIAbility isolation/named-process/child-process mechanisms to 2-in-1/tablets. Therefore, “phones cannot have another application process” is an incorrect conclusion.

The official ExtensionAbility overview distinguishes system-defined scenarios. Third parties can implement suitable Action, Share, Form and other listed extension types; generic ServiceExtension/DataShare implementations are system-only. AppServiceExtension remains a separate enterprise/2-in-1 restriction, as recorded in [the SDK capability note](phone-process-host-capabilities-sdk26-2026-10-09.md).

### 2. A legitimate extension is a possible feature boundary, not an established transparent engine host

The question is not whether a UIExtension process can execute native library code; the unestablished contract is using one as an arbitrary private daemon behind the existing workbench.

- `startAbilityByType` on UIAbilityContext must be invoked from the foreground/main thread (SDK `application/UIAbilityContext.d.ts:934-985`).
- Official `start-intent-panel.md` describes a vertical-domain panel and user selection among applications that match a declared scenario (navigation, finance, mail, flight, express, etc.). It is not documented as direct launch of an arbitrary database service.
- A genuine SQL-file share/action feature could have useful work inside its actual extension session. Its UI, launch conditions, session communication and stop-on-session-end behavior would need to match that scenario. Such a feature has not been shown to provide a persistent engine to the current separate workbench UI.
- A process-mode field does not keep the extension alive after its system-managed scenario/session ends. Reusing an unrelated type or publishing misleading capability declarations would not establish a legitimate architecture.

The installed `UIExtensionContentSession` provides UI/session operations, including page loading and termination/result handling. This research does not assume a general public arbitrary-RPC endpoint from the mere presence of that class.

### 3. A real companion app creates a real process, but the background contract is still missing

A separately installed companion has its own application process and can expose an actual user-facing UIAbility. Official [Application Redirection](https://github.com/openharmony/docs/blob/master/en/application-dev/application-models/link-between-apps-overview.md) lines 10, 22-33 documents opening a target application page using an app link (`openLink`/`startAbility`) or an explicit ability.

That supplies a legitimate visible launch path. It does not, by itself, supply a hidden persistent service while the user returns to the original app.

#### Local UIAbility Call is not an ordinary cross-app background-RPC exemption

The installed `application/UIAbilityContext.d.ts:302-365` documents `startAbilityByCall`:

- Cross-device caller/callee belong to the same application.
- **Same-device** caller/callee belong to different applications, and the caller needs `ohos.permission.ABILITY_BACKGROUND_COMMUNICATION`, explicitly available only to system applications (`:313-314`).
- Calling from the background additionally requires system-only `START_ABILITIES_FROM_BACKGROUND` (`:316-317`).
- A nested API 11+ annotation mentions `DISTRIBUTED_DATASYNC` and DSoftBus verification (`:325-330`). That annotation must not be read as erasing the explicit same-device requirement. This task concerns two apps on one phone, not cross-device continuation.

`connectServiceExtensionAbility` is publicly declared for consumers (`UIAbilityContext.d.ts:685-719`), but it needs an eligible ServiceExtensionAbility producer. It does not authorize an ordinary companion app to implement a generic system-only service.

These limits do not rule out every possible cross-app transport. They rule out treating these particular APIs as a ready, public local database-service endpoint.

#### Continuous tasks require a matching workload and, for generic computing, an ACL

Official `task-management/continuous-task.md`:

- Line 14: continuous tasks are perceivable work, checked for matching behavior; users can cancel them through the notification.
- Lines 23-33: the categories include transfer, media, location, Bluetooth, VoIP, task keeping and limited special scenarios.
- Line 31: `TASK_KEEPING` is PC/2-in-1, or (since API 21) other devices holding `KEEP_BACKGROUND_RUNNING_SYSTEM` ACL.
- Lines 63-79: only UIAbility requests them in the stage model; cross-app/cross-device requests are system-only; mismatched/completed/excessively heavy tasks may be suspended or terminated.
- Line 69: an eligible continuous task prevents suspension for that application’s processes; it does not grant a different application’s eligibility.

SDK `@ohos.resourceschedule.backgroundTaskManager.d.ts:1204-1216,1321-1333` confirms task-keeping restrictions. Its `:1347-1373` restricts special-scenario processing to matching subtypes such as media export/casting, user authorization and a special ACL (API 24+) or the previous system ACL. It is not an unqualified generic database exemption.

A SQL engine waiting for queries cannot be described as media playback or a file upload just to obtain those lifetimes. A visible companion that hosts its own editor may be a different legitimate product shape; no supported invisible general database-service lifetime has been demonstrated here.

#### Storage and IPC must be redesigned explicitly

The current workbench uses a private Unix socket, with TCP fallback forbidden by `.trellis/spec/backend/mysql-workspace.md`. Parent's correct runtime root is `/data/storage/el2/base/haps/entry/files/mysql`.

Official `file-management/app-sandbox-directory.md:10-27` states that app directories are isolated by permissions and namespace. The same textual sandbox pathname in two apps is not automatically the same accessible socket or data directory. Another app cannot simply reuse this path.

The SDK does contain `Context.getGroupDir` (`application/Context.d.ts:240-272`) for a system-assigned group ID, with only EL2 supported for the documented Promise form. This confirms an explicit shared-directory mechanism exists; it does not demonstrate eligibility or Unix-socket IPC for these two ordinary apps. Those group requirements were not investigated further, and must not be inferred from matching signatures or package names.

A proposed companion would therefore need a separately verified endpoint/discovery/authentication contract, lifecycle/cancellation handling, and storage ownership. App links/Ability results can transfer finite requests/results; they are not a proven persistent MySQL connection. Loopback TCP would change the accepted transport contract and would still not solve suspension. No such companion protocol or shared directory is implemented or tested in this task.

### Practical conclusion

- The new isolation fields do not unblock the current ordinary-phone package.
- Genuine specialized extension features and visible companion applications remain real platform capabilities; they should not be blanket-rejected.
- No reviewed combination currently supplies transparent launch, sustained lifetime, private IPC and fresh-server restart for the existing MySQL workbench.
- The dedicated-thread approach is a different engineering direction and is assessed in [the lifecycle note](phone-thread-host-lifecycle-2026-10-09.md). It avoids process-launch restrictions but requires adapting the standalone Oracle lifecycle.

### Files found / related specs

SDK-relative paths use the root stated above:

- `ets/oh-uni-package.json`: API 26/version metadata.
- `ets/api/@ohos.app.ability.EmbeddedUIExtensionAbility.d.ts`: cross-process embedding and device restriction.
- `ets/api/@ohos.app.ability.ActionExtensionAbility.d.ts`: genuine content-processing scenario and API 26 deprecation.
- `ets/api/@ohos.app.ability.UIExtensionAbility.d.ts`: inheritance and host-window lifecycle.
- `ets/api/@ohos.app.ability.UIExtensionContentSession.d.ts`: session/UI operations.
- `ets/api/application/UIAbilityContext.d.ts`: UI launch, Call, service connection and typed-intent launch contracts.
- `ets/api/@ohos.resourceschedule.backgroundTaskManager.d.ts`: continuous-task type and ACL requirements.
- `ets/api/application/Context.d.ts`: private directories and explicit group directory API.
- `ohos/entry/src/main/ets/plugins/QfliMysqlRuntime.ets`: current two-stage host lifecycle and private runtime paths.
- `.trellis/workflow.md`: role-isolated research and persistence.
- `.trellis/spec/backend/mysql-workspace.md`: real Oracle, private Unix socket and phone acceptance.
- `research/ohos-resume-2026-10-09.md`: Pi owns implementation; parent owns device testing.

### External references

Official OpenHarmony master documentation retrieved on 2026-10-09; moving references, not immutable phone-firmware contracts:

1. [Module configuration](https://github.com/openharmony/docs/blob/master/en/application-dev/quick-start/module-configuration-file.md): raw lines 320, 325, 500 and 503, distinguishing ability and extension process controls.
2. [Stage process model](https://github.com/openharmony/docs/blob/master/en/application-dev/application-models/process-model-stage.md): raw lines 18-21, 32-39, real extension processes and device-specific UIAbility process controls.
3. [ExtensionAbility overview](https://github.com/openharmony/docs/blob/master/en/application-dev/application-models/extensionability-overview.md): eligible scenario types and system-managed lifecycles.
4. [Typed application/intent panel](https://github.com/openharmony/docs/blob/master/en/application-dev/application-models/start-intent-panel.md): scenario matching and user selection.
5. [Application redirection](https://github.com/openharmony/docs/blob/master/en/application-dev/application-models/link-between-apps-overview.md): raw lines 10, 22-33, legitimate target-page launch.
6. [Continuous tasks](https://github.com/openharmony/docs/blob/master/en/application-dev/task-management/continuous-task.md): raw lines 14-33, 63-79, task-specific lifetime and computing ACL.
7. [Application sandbox](https://github.com/openharmony/docs/blob/master/en/application-dev/file-management/app-sandbox-directory.md): raw lines 10-27, per-app namespace and access isolation.

## Caveats / Not Found

- No extension, companion app, shared group, IPC protocol, continuous task, or child startup was implemented or tested on the phone.
- OpenHarmony public master and installed SDK establish the cited public contracts; neither proves implementation identity with the closed phone runtime.
- Deprecation of ActionExtensionAbility is not evidence of immediate runtime unavailability.
- No broad claim is made that every possible phone extension or cross-app IPC technique is impossible.
- The actual missing requirement is a complete supported launch/lifetime/transport design for this database workflow. It was not established by the mechanisms above.
- No code, spec, platform configuration or git state was changed by this research.

