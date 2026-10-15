import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:qfli_studio_core/content/content_repository.dart';

/// App-local SQL content repository.
///
/// The SQL app ships its own curriculum assets under `assets/content/` so it is
/// independent of the shared multi-language aggregate. This repository loads
/// both documents, delegates parsing to the shared [ContentCatalog.fromJson]
/// contract, applies [ContentFilter] to select the `sql` entries, and caches the
/// parsed catalog for the lifetime of the instance.
///
/// The shared `LocalTutorialsTab` / `ExampleCodeTab` accept a
/// [ContentRepository] through their `repository:` parameter, so the UI injects
/// a `SqlContentRepository()` and needs no shared-package change.
class SqlContentRepository implements ContentRepository {
  SqlContentRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const String tutorialAsset = 'assets/content/sql_tutorials.json';
  static const String exampleAsset = 'assets/content/sql_examples.json';

  final AssetBundle _bundle;

  Future<ContentCatalog>? _catalogFuture;

  @override
  Future<ContentCatalog> load() => _catalogFuture ??= _loadCatalog();

  @override
  Future<List<TutorialContent>> tutorials({
    ContentFilter filter = const ContentFilter(),
  }) async {
    final catalog = await load();
    return [
      for (final tutorial in catalog.tutorials)
        if (filter.matches(tutorial)) tutorial,
    ];
  }

  @override
  Future<List<ExampleContent>> examples({
    ContentFilter filter = const ContentFilter(),
  }) async {
    final catalog = await load();
    return [
      for (final example in catalog.examples)
        if (filter.matches(example)) example,
    ];
  }

  Future<ContentCatalog> _loadCatalog() async {
    final tutorialsSource = await _loadString(tutorialAsset);
    final examplesSource = await _loadString(exampleAsset);
    return ContentCatalog.fromJson(
      tutorialsSource: tutorialsSource,
      examplesSource: examplesSource,
    );
  }

  /// Loads an app-local asset.
  ///
  /// In a dependent package the key carries a package prefix; inside this app it
  /// does not. Try the plain key first, then the package-qualified form, and
  /// report every failure if neither resolves.
  Future<String> _loadString(String asset) async {
    final keys = <String>[asset, 'packages/qfli_sql/$asset'];
    final failures = <String>[];
    for (final key in keys) {
      try {
        return await _bundle.loadString(key);
      } on FlutterError catch (error) {
        failures.add('$key: ${error.message}');
      } on Exception catch (error) {
        failures.add('$key: $error');
      }
    }
    throw SqlContentAssetException(asset, failures);
  }
}

/// Raised when a local SQL content asset cannot be resolved or read.
class SqlContentAssetException implements Exception {
  const SqlContentAssetException(this.asset, this.failures);

  final String asset;
  final List<String> failures;

  @override
  String toString() =>
      'Unable to load SQL content asset $asset: ${failures.join(' | ')}';
}
