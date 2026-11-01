# Full SQL gate: current-main source binding

## 1. Scope and trigger

The full wrapper previously froze the entire isolated review but compared main
only with the four focused Dart files. That left current main changes outside
those four files unbound. Substantive omissions included lib/main.dart,
lib/local_mysql_runtime.dart, test/startup_test.dart and
integration_test/mysql_ohos_probe.dart. Main pubspec also adds the direct dev
dependency path_provider_platform_interface.

Five audited sources differ only in newline bytes. That does not establish
stale semantics. The assets match. The collector also differs in newline bytes;
its existing comparison already rejects unequal bytes. This change does not
replace those facts with a claim of semantic drift.

Ownership covers only ignored build/offline-ide-check/workspace/run-full-sql-gate.py,
its launch template and this research note. The frozen focused helper, focused
launch, coordinator, product files and isolated review are unchanged by this
implementer. Root prepares review separately. No SDK, formatter, analyzer,
tests, controls, build, native, device or WSL action is authorized here.

Pre-edit copies reside in
build/offline-ide-check/workspace/full-main-binding-preedit-20261026-20261025222725817/.
Original wrapper SHA256:
5476622e388a5bf2aa6d8d2df02f71609dacd876c596b786094ee07688fcefb5.
Original template SHA256:
11ac95f50e7446150d19186c56b38903af9626432613746656a6be77c21c79e6.

## 2. Exact field signatures

The existing schema remains version 1. New fields are mandatory for an accepted
frozen launch. The template deliberately leaves all of them null.

| Field | Required frozen value |
| --- | --- |
| expectedCurrentMainDartSha256 | Object mapping every relative POSIX Dart path under main lib, test, integration_test to its lowercase 64-hex byte SHA256. Exact path set equality is required. |
| expectedMainConfigSha256 | Object mapping every present main CONFIG_FILES path to its byte SHA256. Absent files have no entry. |
| expectedReviewConfigSha256 | Equivalent exact map for isolated review. |
| expectedPathRebindings | Object with exactly pubspec.yaml and pubspec.lock keys. Each value is a duplicate-free list selected from qfli_studio_core, re_editor. |
| focusedInitialSha256 | Byte SHA256 of actual successful focused evidence initial.json. |

CONFIG_FILES contains pubspec.yaml, pubspec.lock, pubspec_overrides.yaml,
analysis_options.yaml and .dart_tool/package_config.json. Existing focused final,
after, terminal-receipt, review, core and supplemental bindings retain their
meanings. Planned expectedPathRebindings value:

    {"pubspec.yaml": [], "pubspec.lock": ["qfli_studio_core", "re_editor"]}

## 3. Contracts and preparation order

Before focused freeze, root preserves old review inputs and copies every main
Dart file byte-exact. Root separately removes stale review Dart paths. Root
copies current pubspec, lock and analysis options bytes. Root changes only the
two declared lock package paths from main relative paths to published immutable
core paths and changes their paired relative:true fields to false. Root retains
the direct-dev declaration and lock marker. No global newline conversion is
allowed for those files. Root has reported its separate source-only preparation
in build/offline-ide-check/workspace/source-current-main-preparation-20261026/preparation.json.
That report does not supply focused/full success evidence.

Main remains preformat after the focused run. The immutable helper final.json
preformatSourceSha256 must contain exactly its four SOURCES. Those hashes must
equal current main and focused initial.json sql. Every initial Dart entry must
equal the complete main map. Initial and postformat captured path sets must
match. Every captured file outside the four focused paths must retain its
initial bytes, including config/native inputs. Postformat must equal actual
focused after.json sql, full launch review map and current review capture. This
permits four formatting changes without copying formatted output into main.

Review pubspec/lock must equal main bytes after only explicitly listed package
path replacements. Pubspec rebindings, if listed, select the same immutable
core and its vendor/re_editor. The planned pubspec list is empty. Lock rebinding
accepts current main double-quoted relative paths with paired relative:true.
Unsupported declaration layouts refuse. Only those two packages are allowed.

Main and review overrides may each be absent or contain only the exact immutable
core and/or re_editor path entries, using LF or CRLF. Both entry orders are
accepted. Review analysis options must match main byte-exact. Package configs
are independently frozen. Their package sets and non-root package metadata must
match. Resolved roots must match except for SQL/native checkout relocation and
the approved core/re_editor export rebinding. Main may resolve its original
sibling core or the immutable export. Its re_editor must select that same core.
Review core and re_editor must select the immutable export. Generated top-level
package-config metadata is separately hash-bound without imposing byte parity.

Focused before.json must match its hash retained in the actual focused final
evidenceHashes map. Its complete SQL/core maps must equal after.json. Together
with the initial-to-after four-file restriction, this proves the initial,
postformat-before-validation and after-validation lineage.

The full gate records mainDart, mainConfig, reviewConfig in both before and
after evidence. It recaptures complete main Dart/config sets and review configs
after validation. New, missing or changed paths prevent success. Review, core,
supplemental and isolated collector/assets checks remain active.

Only actual focused three-case PASS plus actual parent-observed outer terminal
release can populate success prerequisites. Root may fill preparation source
data first. It must leave the refusing status and focused success fields
unfilled until real evidence exists. Freeze the wrapper hash after independent
review. Every runtime still needs a new named grant.

## 4. Error matrix

| Condition | Result |
| --- | --- |
| Template status or focused prerequisites remain unfilled | Existing preflight refusal. |
| Main adds, removes or changes a Dart file | Main map mismatch before run, or sourcesStable.mainDart false after run. |
| Review misses a main Dart path or adds a stale path | Initial manifest or review Dart set mismatch. |
| Non-focused Dart bytes differ, including only newlines | Byte parity refusal. No canonicalization exception. |
| Focused initial and after differ outside four SOURCES | Focused lineage refusal before full controls. |
| Main focused bytes were replaced with formatted output | Preformat lineage refusal. Prepare a new binding if intentional. |
| Review omits direct dev dependency or lock marker | Declaration parity refusal even with newly frozen review hashes. |
| Lock still selects old core export | Exact core path transformation mismatch. |
| Rebinding list names another package or repeats a name | Explicit-list refusal. |
| Either checkout adds an override beyond exact immutable core/re_editor entries | Override contract refusal. |
| Package sets, non-root package metadata or unapproved resolved roots differ | Dependency parity refusal. |
| Focused before.json is absent, hash-mismatched or differs from after.json | Postformat lineage refusal. |
| Config path appears, disappears or changes after preflight | MainConfig or reviewConfig stability false. |
| Focused pass or actual parent terminal release is absent | Existing focused/receipt refusal remains mandatory. |

## 5. Good, base and bad evidence

Good future evidence starts with the complete main Dart path/hash inventory,
byte-exact review preparation and explicit dependency rebindings. Real focused
PASS changes only four permitted paths. Actual parent release binds the real
outer handle, PID, exit and empty Jobs. Full validation retains every recorded
main/review/core/config/supplemental snapshot.

The base is SOURCE PREPARED / UNRUN. No gate ran in this implementation turn.
The template remains refusing. Source hashes and static syntax checks establish
preparation only. They do not establish focused/full/native acceptance.

Bad evidence freezes stale review hashes while ignoring main, calls a new direct
dependency a core rebind, substitutes formatted main bytes without new lineage,
treats LF/CRLF differences as semantic drift, or fills success from a failure
receipt.

## 6. Checks and future tests required

Authorized checks here are AST parsing, JSON data parsing, byte hashes, diff
inspection and whitespace checks. Do not import or invoke either gate or helper.
No runtime regression suite was executed or added.

A later authorized window should cover valid complete preparation;
new/missing/changed main Dart preflight and postrun; extra/missing review Dart;
non-focused newline-only drift; valid four-file formatting; non-focused focused
mutation; forged preformat map; absent initial proof; omitted direct-dev
declaration/lock marker; old core lock paths; valid two-package rebindings;
unauthorized overrides; config add/remove/change; absent focused PASS; and
absent parent release. Preflight mismatches must refuse before full controls.
Postrun drift must prevent a successful final report.

Independent source review fixed three local gaps: missing authenticated
before.json lineage, rejection of legitimate main immutable-core overrides,
and absence of semantic package-config parity beyond the two reviewed roots.
The revised wrapper SHA256 is
6a539570c54654f1f5f29fb5ba873a6c5e9b5ef612991ca4e59703df234e4802.
The revised refusing template SHA256 is
f2da2948e2ab744a18317ea097f4937c45550df8679a9bfd598a6f7199eea06b.
AST parsing, JSON parsing, refusing-prerequisite checks and whitespace checks
passed. Lint, type-check and runtime tests remain UNRUN under the source-only
restriction. Neither gate nor helper was imported or invoked.

## 7. Wrong and correct

Wrong: compare four main files with formatted review and declare all main
source current. Correct: bind the whole main inventory to focused initial bytes
and permit only four reviewed formatting changes in review.

Wrong: normalize every pubspec/lock difference or trust arbitrary frozen review
hashes. Correct: copy current declarations, authorize only two named path
rebindings and compare every remaining byte.

Wrong: copy formatted files into main for naive equality. Correct: preserve
preformat main and prove initial-to-postformat lineage.

Wrong: claim a pass or reuse a reservation after this source edit. Correct:
obtain independent source review, re-freeze prepared inputs and seek new named
focused/full windows in the required terminal-release order.
