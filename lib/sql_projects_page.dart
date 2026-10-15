import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/services/task_activity_service.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/widgets/project_card.dart';
import 'package:qfli_studio_core/widgets/project_dialogs.dart';

/// Standalone project list for the SQL app.
///
/// This is a real, single-toolbar project page: it owns ONE `AppBar` titled
/// "项目" with a back button and a search field, plus a create action. It uses
/// the shared public project APIs directly (`ProjectStore`, `ProjectCard`,
/// `ProjectDialogs`, `EditorPage`) instead of embedding the shared `HomeTab`
/// shell, which carries its own app bar and app-level navigation. There is no
/// second home rail/PageView here.
class SqlProjectsPage extends StatefulWidget {
  const SqlProjectsPage({
    super.key,
    required this.store,
    required this.auth,
    required this.settings,
    this.embedded = false,
  });

  final ProjectStore store;
  final AuthStore auth;
  final SettingsStore settings;

  /// When true the page is hosted as a destination inside [SqlHomeShell]: it
  /// keeps its single toolbar but drops the "返回数据库" affordance, because
  /// 数据库 is now a sibling tab rather than the parent route.
  final bool embedded;

  @override
  State<SqlProjectsPage> createState() => _SqlProjectsPageState();
}

class _SqlProjectsPageState extends State<SqlProjectsPage> {
  final _searchController = TextEditingController();
  bool _searchOpen = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (!widget.store.loaded) unawaited(widget.store.load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Project> get _visible {
    final normalized = _query.trim().toLowerCase();
    final projects =
        widget.store.projects
            .where((project) => !_offlineOnly || !project.isCloud)
            .toList()
          ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    if (normalized.isEmpty) return projects;
    return projects
        .where(
          (project) =>
              project.name.toLowerCase().contains(normalized) ||
              project.path.toLowerCase().contains(normalized),
        )
        .toList();
  }

  bool get _offlineOnly => StudioProfile.current?.isOffline == true;

  void _reportActivity(String event) {
    if (!_offlineOnly) TaskActivityService.report(widget.auth, event);
  }

  Future<void> _createProject() async {
    final result = await showCreateProjectDialog(context, widget.store);
    if (result != null && mounted) {
      _reportActivity('create_project');
      await _openProject(result.project, initialOpenFile: result.openFile);
    }
  }

  Future<void> _openProject(Project project, {String? initialOpenFile}) async {
    if (_offlineOnly && project.isCloud) return;
    if (!project.isCloud && !Directory(project.path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            StudioLocalizations.of(context).missingProjectPath(project.path),
          ),
          action: SnackBarAction(
            label: StudioLocalizations.of(context).removeFromList,
            onPressed: () => widget.store.remove(project),
          ),
        ),
      );
      return;
    }
    widget.store.touch(project);
    _reportActivity('open_project');
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorPage(
          project: project,
          store: widget.store,
          auth: widget.auth,
          settings: widget.settings,
          initialOpenPath: initialOpenFile,
        ),
      ),
    );
  }

  Future<void> _deleteProject(Project project) async {
    final confirmed = await showDeleteProjectConfirm(context, project);
    if (!confirmed) return;
    await widget.store.deleteProject(project);
  }

  Future<void> _addExisting() async {
    final project = await showAddExistingDialog(context, widget.store);
    if (project != null && mounted) {
      _reportActivity('add_existing_project');
    }
  }

  /// Removes registry records whose local directory is gone (no disk delete).
  Future<void> _removeMissing() async {
    final missing = widget.store.projects
        .where((p) => !p.isCloud && !Directory(p.path).existsSync())
        .toList();
    if (missing.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(StudioLocalizations.of(context).noMissingProjects),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = StudioLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.removeMissingTitle),
          content: Text(
            l10n.removeMissingMessage(
              missing.length,
              missing.map((p) => '· ${p.name}').join('\n'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.remove),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      for (final project in missing) {
        widget.store.remove(project);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.embedded
            ? null
            : IconButton(
                tooltip: '返回数据库',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
        title: _searchOpen
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索项目',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _query = value),
              )
            : const Text('项目'),
        actions: [
          IconButton(
            tooltip: _searchOpen ? '关闭搜索' : '搜索项目',
            icon: Icon(_searchOpen ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen) {
                _query = '';
                _searchController.clear();
              }
            }),
          ),
          PopupMenuButton<String>(
            tooltip: StudioLocalizations.of(context).more,
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'add_existing':
                  unawaited(_addExisting());
                case 'remove_missing':
                  unawaited(_removeMissing());
              }
            },
            itemBuilder: (_) => [
              if (AppPaths.isDesktop)
                PopupMenuItem(
                  value: 'add_existing',
                  child: Row(
                    children: [
                      const Icon(Icons.folder_open_outlined, size: 20),
                      const SizedBox(width: 12),
                      Text(StudioLocalizations.of(context).addExistingProject),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'remove_missing',
                child: Row(
                  children: [
                    const Icon(Icons.folder_delete_outlined, size: 20),
                    const SizedBox(width: 12),
                    Text(StudioLocalizations.of(context).removeMissingProjects),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProject,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('新建项目'),
      ),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          if (!widget.store.loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          final projects = _visible;
          if (projects.isEmpty) {
            return Center(
              child: Text(
                _query.trim().isEmpty ? '暂无项目，点击“新建项目”。' : '没有匹配的项目。',
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final project = projects[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ProjectCard(
                  project: project,
                  onOpen: () => unawaited(_openProject(project)),
                  onRemove: () => unawaited(_deleteProject(project)),
                  onToggleFavorite: (value) =>
                      widget.store.setFavorite(project, value),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
