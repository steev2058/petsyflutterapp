import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../data/syria_cities.dart';
import '../services/geo_service.dart';
import 'common.dart';

/// Shared Syrian-governorate picker with optional GPS autofill.
class PetsyCityField extends StatefulWidget {
  const PetsyCityField({
    super.key,
    this.controller,
    this.value,
    this.onChanged,
    this.onCitySelected,
    this.label,
    this.hint,
    this.required = false,
    this.enabled = true,
    this.autofillFromGps = true,
    this.validator,
  });

  final TextEditingController? controller;
  final String? value;
  final ValueChanged<String>? onChanged;
  final ValueChanged<SyriaCity>? onCitySelected;
  final String? label;
  final String? hint;
  final bool required;
  final bool enabled;
  final bool autofillFromGps;
  final FormFieldValidator<String>? validator;

  @override
  State<PetsyCityField> createState() => _PetsyCityFieldState();
}

class _PetsyCityFieldState extends State<PetsyCityField> {
  final _fieldKey = GlobalKey<FormFieldState<String>>();
  late String _value = _resolveInitial();
  bool _detecting = false;
  bool _didAutofill = false;

  String _resolveInitial() {
    final raw = (widget.controller?.text ?? widget.value ?? '').trim();
    final match = findSyriaCity(raw);
    if (match != null) return syriaCityStorageLabel(match);
    return raw;
  }

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_syncFromController);
    if (widget.autofillFromGps && _value.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _detectGps(silent: true));
    }
  }

  @override
  void didUpdateWidget(covariant PetsyCityField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_syncFromController);
      widget.controller?.addListener(_syncFromController);
      setState(() => _value = _resolveInitial());
    } else if (widget.value != oldWidget.value && widget.controller == null) {
      setState(() => _value = (widget.value ?? '').trim());
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_syncFromController);
    super.dispose();
  }

  void _syncFromController() {
    final next = (widget.controller?.text ?? '').trim();
    final match = findSyriaCity(next);
    final normalized = match != null ? syriaCityStorageLabel(match) : next;
    if (normalized != _value && mounted) setState(() => _value = normalized);
  }

  void _apply(SyriaCity city) {
    final label = syriaCityStorageLabel(city);
    widget.controller?.text = label;
    setState(() => _value = label);
    _fieldKey.currentState?.didChange(label);
    widget.onChanged?.call(label);
    widget.onCitySelected?.call(city);
  }

  Future<void> _detectGps({bool silent = false}) async {
    if (!widget.enabled || _detecting) return;
    if (silent && _didAutofill) return;
    setState(() => _detecting = true);
    try {
      final result = await GeoService.instance.detectCityFromGps();
      if (!mounted) return;
      if (result.location.denied) {
        if (!silent) context.snack(context.t('location_permission_denied'), error: true);
        return;
      }
      if (result.location.serviceDisabled) {
        if (!silent) context.snack(context.t('location_disabled'), error: true);
        return;
      }
      final city = result.city;
      if (city == null) {
        if (!silent) context.snack(context.t('city_gps_failed'), error: true);
        return;
      }
      _didAutofill = true;
      _apply(city);
      if (!silent) {
        context.snack(
          context.t('city_gps_detected').replaceAll('{city}', city.label(Localizations.localeOf(context).languageCode)),
          success: true,
          icon: Icons.my_location_rounded,
        );
      }
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  Future<void> _openPicker() async {
    if (!widget.enabled || _detecting) return;
    final selected = await showModalBottomSheet<SyriaCity>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _CityPickerSheet(
        selected: findSyriaCity(_value),
        detecting: _detecting,
        onDetectGps: () async {
          Navigator.pop(ctx);
          await _detectGps();
        },
      ),
    );
    if (selected != null && mounted) _apply(selected);
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final match = findSyriaCity(_value);
    final display = match?.label(locale) ?? (_value.isEmpty ? null : _value);

    return FormField<String>(
      key: _fieldKey,
      initialValue: _value,
      validator: widget.validator ??
          (widget.required
              ? (v) => (v == null || v.trim().isEmpty) ? context.t('required') : null
              : null),
      builder: (state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: PetsyColors.surface,
              borderRadius: BorderRadius.circular(PetsyRadius.md),
              child: InkWell(
                onTap: widget.enabled ? _openPicker : null,
                borderRadius: BorderRadius.circular(PetsyRadius.md),
                child: InputDecorator(
                  isEmpty: display == null,
                  decoration: InputDecoration(
                    labelText: widget.label ?? context.t('city'),
                    hintText: widget.hint ?? context.t('city_pick_hint'),
                    prefixIcon: const Icon(Icons.location_city_outlined),
                    suffixIcon: _detecting
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.2),
                            ),
                          )
                        : IconButton(
                            tooltip: context.t('use_my_location'),
                            onPressed: widget.enabled ? () => _detectGps() : null,
                            icon: const Icon(Icons.my_location_rounded),
                          ),
                    errorText: state.errorText,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(PetsyRadius.md)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(PetsyRadius.md),
                      borderSide: BorderSide(
                        color: state.hasError ? PetsyColors.error : PetsyColors.border,
                      ),
                    ),
                  ),
                  child: Text(
                    display ?? (widget.hint ?? context.t('city_pick_hint')),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: display == null ? PetsyColors.textLight : PetsyColors.text,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: widget.enabled && !_detecting ? () => _detectGps() : null,
                icon: _detecting
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.gps_fixed_rounded, size: 16),
                label: Text(context.t('city_use_gps')),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CityPickerSheet extends StatelessWidget {
  const _CityPickerSheet({
    required this.selected,
    required this.detecting,
    required this.onDetectGps,
  });

  final SyriaCity? selected;
  final bool detecting;
  final VoidCallback onDetectGps;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.72),
        decoration: BoxDecoration(
          color: PetsyColors.surface,
          borderRadius: BorderRadius.circular(PetsyRadius.xl),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: PetsyColors.border, borderRadius: BorderRadius.circular(99)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.t('city_pick_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                        const SizedBox(height: 2),
                        Text(
                          context.t('city_pick_subtitle'),
                          style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.t('city_use_gps'),
                    onPressed: detecting ? null : onDetectGps,
                    icon: detecting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
                        : const Icon(Icons.my_location_rounded, color: PetsyColors.primaryDark),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: syriaCities.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final city = syriaCities[i];
                  final isSelected = selected?.id == city.id;
                  return Material(
                    color: isSelected ? PetsyColors.primarySoft : PetsyColors.backgroundAlt,
                    borderRadius: BorderRadius.circular(PetsyRadius.md),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(PetsyRadius.md),
                      onTap: () => Navigator.pop(context, city),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isSelected ? PetsyColors.primary : Colors.white,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color: isSelected ? PetsyColors.primaryDark : PetsyColors.border,
                                ),
                              ),
                              child: Icon(
                                Icons.location_on_rounded,
                                size: 18,
                                color: isSelected ? Colors.white : PetsyColors.primaryDark,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    city.label(locale),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: isSelected ? PetsyColors.primaryDark : PetsyColors.text,
                                    ),
                                  ),
                                  Text(
                                    locale == 'ar' ? city.en : city.ar,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: PetsyColors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle_rounded, color: PetsyColors.primary, size: 20),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
