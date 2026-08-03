import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/media_repository.dart';
import '../../models/app_profile.dart';
import '../../models/media_item.dart';
import '../app_theme.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.items,
    required this.repository,
    required this.profile,
    required this.onProfileChanged,
    required this.onCollectionChanged,
    required this.onLogout,
  });
  final List<MediaItem> items;
  final MediaRepository repository;
  final AppProfile profile;
  final ValueChanged<AppProfile> onProfileChanged;
  final Future<void> Function() onCollectionChanged;
  final Future<void> Function() onLogout;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _diagnostics;
  String? _diagnosticsError;
  bool _diagnosticsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDiagnostics();
  }

  Future<void> _loadDiagnostics() async {
    setState(() {
      _diagnosticsLoading = true;
      _diagnosticsError = null;
    });
    try {
      final value = await widget.repository.loadDiagnostics();
      if (mounted) setState(() => _diagnostics = value);
    } catch (error) {
      if (mounted) setState(() => _diagnosticsError = error.toString());
    } finally {
      if (mounted) setState(() => _diagnosticsLoading = false);
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: widget.profile.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Имя профиля'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Имя'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.length < 2) return;
    widget.onProfileChanged(
      await widget.repository.saveProfile(widget.profile.copyWith(name: name)),
    );
  }

  Future<void> _editTaste() async {
    final selected = widget.profile.favoriteGenres.toSet();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Настроить вкус'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final genre in _availableGenres)
                  FilterChip(
                    label: Text(genre),
                    selected: selected.contains(genre),
                    onSelected: (value) => setDialogState(() {
                      value ? selected.add(genre) : selected.remove(genre);
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    widget.onProfileChanged(
      await widget.repository.saveProfile(
        widget.profile.copyWith(favoriteGenres: result.toList()..sort()),
      ),
    );
  }

  Future<void> _toggleTheme(bool value) async {
    widget.onProfileChanged(
      await widget.repository.saveProfile(
        widget.profile.copyWith(darkTheme: value),
      ),
    );
  }

  Future<void> _export() async {
    final value = await widget.repository.exportCollection();
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Коллекция скопирована в буфер обмена.')),
      );
    }
  }

  Future<void> _import() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Импорт коллекции'),
        content: SizedBox(
          width: 620,
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 14,
            decoration: const InputDecoration(
              hintText: 'Вставьте JSON, экспортированный Кадроскопом',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Импортировать'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;
    try {
      await widget.repository.importCollection(value);
      await widget.onCollectionChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Коллекция импортирована.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось импортировать: $error')),
        );
      }
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить коллекцию?'),
        content: const Text(
          'Будут удалены произведения, оценки и отметки эпизодов. Профиль останется.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.clearCollection();
    await widget.onCollectionChanged();
  }

  @override
  Widget build(BuildContext context) {
    final saved = widget.items
        .where((item) => item.status != WatchStatus.none)
        .length;
    final initial = widget.profile.name.trim().isEmpty
        ? '?'
        : widget.profile.name.trim().characters.first.toUpperCase();
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        MediaQuery.sizeOf(context).width < 600 ? 18 : 34,
        24,
        MediaQuery.sizeOf(context).width < 600 ? 18 : 34,
        42,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Профиль', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: AppColors.butter,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.profile.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          widget.profile.isGuest
                              ? 'Гостевой локальный профиль'
                              : widget.profile.email,
                          style: const TextStyle(color: Colors.white60),
                        ),
                      ],
                    ),
                    const SizedBox(width: 24),
                    Text(
                      '$saved в коллекции',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    IconButton(
                      tooltip: 'Изменить имя',
                      onPressed: _editName,
                      color: Colors.white,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Text(
                'Любимые жанры',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (widget.profile.favoriteGenres.isEmpty)
                    const Text(
                      'Пока не выбраны — настройте вкус.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  for (final genre in widget.profile.favoriteGenres)
                    Chip(label: Text(genre)),
                  ActionChip(
                    avatar: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('Настроить вкус'),
                    onPressed: _editTaste,
                  ),
                ],
              ),
              const SizedBox(height: 26),
              _SettingsSection(
                children: [
                  SwitchListTile(
                    value: widget.profile.darkTheme,
                    onChanged: _toggleTheme,
                    secondary: const Icon(Icons.dark_mode_outlined),
                    title: const Text('Тёмная тема'),
                    subtitle: const Text('Переключает оформление приложения'),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    onTap: _export,
                    leading: const Icon(Icons.upload_file_outlined),
                    title: const Text('Экспорт коллекции'),
                    subtitle: const Text('Скопировать JSON в буфер обмена'),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    onTap: _import,
                    leading: const Icon(Icons.download_outlined),
                    title: const Text('Импорт коллекции'),
                    subtitle: const Text(
                      'Вставить ранее экспортированный JSON',
                    ),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    onTap: _clear,
                    leading: const Icon(
                      Icons.delete_sweep_outlined,
                      color: AppColors.coral,
                    ),
                    title: const Text('Очистить локальную базу'),
                    subtitle: const Text('Удалить коллекцию и историю отметок'),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Состояние сервисов',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: _diagnosticsLoading ? null : _loadDiagnostics,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Diagnostics(
                value: _diagnostics,
                error: _diagnosticsError,
                loading: _diagnosticsLoading,
              ),
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: widget.onLogout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Выйти из профиля'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(children: children),
  );
}

class _Diagnostics extends StatelessWidget {
  const _Diagnostics({
    required this.value,
    required this.error,
    required this.loading,
  });
  final Map<String, dynamic>? value;
  final String? error;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    if (loading) return const LinearProgressIndicator(color: AppColors.accent);
    if (error != null) {
      return _DiagnosticRow(
        label: 'Backend',
        status: 'недоступен',
        ok: false,
        detail: error,
      );
    }
    final providers =
        (value?['providers'] as Map?)?.cast<String, dynamic>() ?? const {};
    final tmdb =
        (providers['tmdb'] as Map?)?.cast<String, dynamic>() ?? const {};
    final anilist =
        (providers['anilist'] as Map?)?.cast<String, dynamic>() ?? const {};
    final ai = (value?['ai'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const _DiagnosticRow(label: 'Backend', status: 'подключён', ok: true),
          const Divider(height: 1, indent: 56),
          _DiagnosticRow(
            label: 'TMDB',
            status: _providerStatus(tmdb['status'] as String?),
            ok: tmdb['status'] == 'connected',
            detail: tmdb['message'] as String?,
          ),
          const Divider(height: 1, indent: 56),
          _DiagnosticRow(
            label: 'AniList',
            status: _providerStatus(anilist['status'] as String?),
            ok: anilist['status'] == 'connected',
            detail: anilist['message'] as String?,
          ),
          const Divider(height: 1, indent: 56),
          _DiagnosticRow(
            label: 'AI provider: ${ai['provider'] ?? 'отключён'}',
            status: _aiStatus(ai['status'] as String?),
            ok: ai['status'] == 'connected',
            detail: ai['message'] as String?,
          ),
        ],
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({
    required this.label,
    required this.status,
    required this.ok,
    this.detail,
  });
  final String label;
  final String status;
  final bool ok;
  final String? detail;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(
      ok ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
      color: ok ? AppColors.accent : AppColors.coral,
    ),
    title: Text(label),
    subtitle: detail == null ? null : Text(detail!),
    trailing: Text(
      status,
      style: TextStyle(color: ok ? AppColors.accent : AppColors.muted),
    ),
  );
}

String _providerStatus(String? value) => switch (value) {
  'connected' => 'подключён',
  'notConfigured' => 'нет ключа',
  'error' => 'ошибка',
  _ => 'ещё не проверен',
};

String _aiStatus(String? value) => switch (value) {
  'connected' => 'подключён',
  'noKey' => 'нет ключа',
  'noFunds' => 'нет средств',
  'disabled' => 'отключён',
  'fallback' => 'готов / fallback',
  _ => 'ошибка',
};

const _availableGenres = [
  'Фантастика',
  'Фэнтези',
  'Приключения',
  'Драма',
  'Комедия',
  'Триллер',
  'Детектив',
  'Ужасы',
  'Романтика',
  'История',
  'Документальное',
  'Семейное',
];
