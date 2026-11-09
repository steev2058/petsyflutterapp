import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';

/// One selectable row in [PetsyChoiceField] / [PetsyMultiChoiceField].
class PetsyChoiceOption<T> {
  const PetsyChoiceOption({
    required this.value,
    required this.label,
    this.icon,
    this.leading,
    this.subtitle,
    this.keywords = const [],
  });

  final T value;
  final String label;
  final IconData? icon;
  final Widget? leading;
  final String? subtitle;
  final List<String> keywords;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (label.toLowerCase().contains(q)) return true;
    if ((subtitle ?? '').toLowerCase().contains(q)) return true;
    for (final k in keywords) {
      if (k.toLowerCase().contains(q)) return true;
    }
    final asText = value?.toString() ?? '';
    return asText.toLowerCase().contains(q);
  }
}

const _kSearchThreshold = 8;

/// Compact single-select field that opens a bottom-sheet list.
class PetsyChoiceField<T> extends StatelessWidget {
  const PetsyChoiceField({
    super.key,
    required this.options,
    required this.onChanged,
    this.value,
    this.label,
    this.hint,
    this.prefixIcon = Icons.list_alt_rounded,
    this.enabled = true,
    this.required = false,
    this.sheetTitle,
    this.sheetSubtitle,
    this.searchable,
  });

  final T? value;
  final List<PetsyChoiceOption<T>> options;
  final ValueChanged<T> onChanged;
  final String? label;
  final String? hint;
  final IconData? prefixIcon;
  final bool enabled;
  final bool required;
  final String? sheetTitle;
  final String? sheetSubtitle;
  final bool? searchable;

  PetsyChoiceOption<T>? get _selected {
    for (final o in options) {
      if (o.value == value) return o;
    }
    return null;
  }

  Future<void> _pick(BuildContext context, FormFieldState<T?>? state) async {
    if (!enabled) return;
    final result = await showPetsyChoiceSheet<T>(
      context: context,
      options: options,
      value: value,
      title: sheetTitle ?? label ?? context.t('select_option'),
      subtitle: sheetSubtitle,
      searchable: searchable ?? options.length >= _kSearchThreshold,
    );
    if (result == null) return;
    onChanged(result.value);
    state?.didChange(result.value);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final display = selected?.label;
    final emptyHint = hint ?? context.t('select_option');

    return FormField<T?>(
      initialValue: value,
      validator: required ? (v) => v == null ? context.t('required') : null : null,
      builder: (state) {
        return Material(
          color: PetsyColors.surface,
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          child: InkWell(
            onTap: enabled ? () => _pick(context, state) : null,
            borderRadius: BorderRadius.circular(PetsyRadius.md),
            child: InputDecorator(
              isEmpty: display == null,
              decoration: InputDecoration(
                labelText: label,
                hintText: emptyHint,
                prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
                suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
                errorText: state.errorText,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(PetsyRadius.md)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(PetsyRadius.md),
                  borderSide: BorderSide(
                    color: state.hasError ? PetsyColors.error : PetsyColors.border,
                  ),
                ),
              ),
              child: Row(
                children: [
                  if (selected?.leading != null) ...[
                    selected!.leading!,
                    const SizedBox(width: 10),
                  ] else if (selected?.icon != null) ...[
                    Icon(selected!.icon, size: 18, color: PetsyColors.primaryDark),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      display ?? emptyHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: display == null ? PetsyColors.textLight : PetsyColors.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Compact multi-select field; sheet confirms with Done.
class PetsyMultiChoiceField<T> extends StatelessWidget {
  const PetsyMultiChoiceField({
    super.key,
    required this.options,
    required this.values,
    required this.onChanged,
    this.label,
    this.hint,
    this.prefixIcon = Icons.checklist_rounded,
    this.enabled = true,
    this.minSelections = 1,
    this.sheetTitle,
    this.sheetSubtitle,
    this.searchable,
  });

  final Set<T> values;
  final List<PetsyChoiceOption<T>> options;
  final ValueChanged<Set<T>> onChanged;
  final String? label;
  final String? hint;
  final IconData? prefixIcon;
  final bool enabled;
  final int minSelections;
  final String? sheetTitle;
  final String? sheetSubtitle;
  final bool? searchable;

  String _summary(BuildContext context) {
    final labels = options.where((o) => values.contains(o.value)).map((o) => o.label).toList();
    if (labels.isEmpty) return hint ?? context.t('select_option');
    if (labels.length <= 2) return labels.join(' · ');
    return context.t('choice_selected_count').replaceAll('{n}', '${labels.length}');
  }

  Future<void> _pick(BuildContext context) async {
    if (!enabled) return;
    final result = await showPetsyMultiChoiceSheet<T>(
      context: context,
      options: options,
      values: values,
      title: sheetTitle ?? label ?? context.t('select_option'),
      subtitle: sheetSubtitle,
      minSelections: minSelections,
      searchable: searchable ?? options.length >= _kSearchThreshold,
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = values.isNotEmpty;

    return Material(
      color: PetsyColors.surface,
      borderRadius: BorderRadius.circular(PetsyRadius.md),
      child: InkWell(
        onTap: enabled ? () => _pick(context) : null,
        borderRadius: BorderRadius.circular(PetsyRadius.md),
        child: InputDecorator(
          isEmpty: !hasValue,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint ?? context.t('select_option'),
            prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
            suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(PetsyRadius.md)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(PetsyRadius.md),
              borderSide: const BorderSide(color: PetsyColors.border),
            ),
          ),
          child: Text(
            _summary(context),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: hasValue ? PetsyColors.text : PetsyColors.textLight,
            ),
          ),
        ),
      ),
    );
  }
}

class PetsyChoiceResult<T> {
  const PetsyChoiceResult(this.value);
  final T value;
}

Future<PetsyChoiceResult<T>?> showPetsyChoiceSheet<T>({
  required BuildContext context,
  required List<PetsyChoiceOption<T>> options,
  T? value,
  String? title,
  String? subtitle,
  bool searchable = false,
}) {
  return showModalBottomSheet<PetsyChoiceResult<T>>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _ChoiceSheet<T>(
      options: options,
      value: value,
      title: title,
      subtitle: subtitle,
      searchable: searchable,
    ),
  );
}

Future<Set<T>?> showPetsyMultiChoiceSheet<T>({
  required BuildContext context,
  required List<PetsyChoiceOption<T>> options,
  required Set<T> values,
  String? title,
  String? subtitle,
  int minSelections = 1,
  bool searchable = false,
}) {
  return showModalBottomSheet<Set<T>>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _MultiChoiceSheet<T>(
      options: options,
      initial: values,
      title: title,
      subtitle: subtitle,
      minSelections: minSelections,
      searchable: searchable,
    ),
  );
}

/// Shared chrome matching the working city picker layout.
class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.child,
    this.header,
    this.search,
  });

  final Widget child;
  final Widget? header;
  final Widget? search;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.72;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: PetsyColors.surface,
            borderRadius: BorderRadius.circular(PetsyRadius.xl),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: PetsyColors.border, borderRadius: BorderRadius.circular(99)),
                ),
              ),
              if (header != null) header!,
              if (search != null) search!,
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceSheet<T> extends StatefulWidget {
  const _ChoiceSheet({
    required this.options,
    required this.value,
    required this.searchable,
    this.title,
    this.subtitle,
  });

  final List<PetsyChoiceOption<T>> options;
  final T? value;
  final bool searchable;
  final String? title;
  final String? subtitle;

  @override
  State<_ChoiceSheet<T>> createState() => _ChoiceSheetState<T>();
}

class _ChoiceSheetState<T> extends State<_ChoiceSheet<T>> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<PetsyChoiceOption<T>> get _filtered =>
      widget.options.where((o) => o.matches(_query.text)).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return _SheetShell(
      header: widget.title == null
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      style: const TextStyle(
                        color: PetsyColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
      search: widget.searchable
          ? Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: TextField(
                controller: _query,
                autofocus: widget.options.length >= 10,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: context.t('search_options'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.t('clear'),
                          onPressed: () => setState(() => _query.clear()),
                          icon: const Icon(Icons.close_rounded),
                        ),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            )
          : null,
      child: filtered.isEmpty
          ? const _EmptyChoiceList()
          : ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final option = filtered[i];
                return _ChoiceTile(
                  option: option,
                  selected: option.value == widget.value,
                  onTap: () => Navigator.pop(context, PetsyChoiceResult(option.value)),
                );
              },
            ),
    );
  }
}

class _MultiChoiceSheet<T> extends StatefulWidget {
  const _MultiChoiceSheet({
    required this.options,
    required this.initial,
    required this.minSelections,
    required this.searchable,
    this.title,
    this.subtitle,
  });

  final List<PetsyChoiceOption<T>> options;
  final Set<T> initial;
  final int minSelections;
  final bool searchable;
  final String? title;
  final String? subtitle;

  @override
  State<_MultiChoiceSheet<T>> createState() => _MultiChoiceSheetState<T>();
}

class _MultiChoiceSheetState<T> extends State<_MultiChoiceSheet<T>> {
  late final Set<T> _selected = {...widget.initial};
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<PetsyChoiceOption<T>> get _filtered =>
      widget.options.where((o) => o.matches(_query.text)).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final canDone = _selected.length >= widget.minSelections;
    final filtered = _filtered;
    return _SheetShell(
      header: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.title != null)
                    Text(widget.title!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      style: const TextStyle(
                        color: PetsyColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: canDone ? () => Navigator.pop(context, Set<T>.from(_selected)) : null,
              child: Text(context.t('done')),
            ),
          ],
        ),
      ),
      search: widget.searchable
          ? Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: context.t('search_options'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.t('clear'),
                          onPressed: () => setState(() => _query.clear()),
                          icon: const Icon(Icons.close_rounded),
                        ),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            )
          : null,
      child: filtered.isEmpty
          ? const _EmptyChoiceList()
          : ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final option = filtered[i];
                final selected = _selected.contains(option.value);
                return _ChoiceTile(
                  option: option,
                  selected: selected,
                  multi: true,
                  onTap: () {
                    setState(() {
                      if (selected) {
                        if (_selected.length > widget.minSelections) {
                          _selected.remove(option.value);
                        }
                      } else {
                        _selected.add(option.value);
                      }
                    });
                  },
                );
              },
            ),
    );
  }
}

class _EmptyChoiceList extends StatelessWidget {
  const _EmptyChoiceList();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded, color: PetsyColors.textLight, size: 36),
          const SizedBox(height: 10),
          Text(
            context.t('no_options'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: PetsyColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.option,
    required this.selected,
    required this.onTap,
    this.multi = false,
  });

  final PetsyChoiceOption<T> option;
  final bool selected;
  final VoidCallback onTap;
  final bool multi;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? PetsyColors.primarySoft : PetsyColors.backgroundAlt,
      borderRadius: BorderRadius.circular(PetsyRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(PetsyRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              if (option.leading != null)
                option.leading!
              else
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected ? PetsyColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: selected ? PetsyColors.primaryDark : PetsyColors.border,
                    ),
                  ),
                  child: Icon(
                    option.icon ?? Icons.check_rounded,
                    size: 18,
                    color: selected ? Colors.white : PetsyColors.primaryDark,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: selected ? PetsyColors.primaryDark : PetsyColors.text,
                      ),
                    ),
                    if ((option.subtitle ?? '').isNotEmpty)
                      Text(
                        option.subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: PetsyColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                multi
                    ? (selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded)
                    : (selected ? Icons.check_circle_rounded : Icons.circle_outlined),
                color: selected ? PetsyColors.primary : PetsyColors.textLight,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
