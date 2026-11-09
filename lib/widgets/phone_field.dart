import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../data/phone_countries.dart';
import 'country_flag.dart';

/// International phone input with flag, dial code, searchable country sheet,
/// per-country length rules, and no leading trunk `0` (dial code is already shown).
class PetsyPhoneField extends StatefulWidget {
  const PetsyPhoneField({
    super.key,
    this.controller,
    this.decoration,
    this.textInputAction,
    this.onChanged,
    this.onCountryChanged,
    this.validator,
    this.enabled = true,
    this.autofocus = false,
    this.required = false,
    this.initialCountryIso,
    this.initialNationalNumber,
  });

  final TextEditingController? controller;
  final InputDecoration? decoration;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<PhoneCountry>? onCountryChanged;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final bool autofocus;
  final bool required;
  final String? initialCountryIso;
  final String? initialNationalNumber;

  /// Full E.164-ish value: `+963957261491`
  static String compose(PhoneCountry country, String national) {
    final local = country.normalizeNational(national);
    if (local.isEmpty) return '';
    return '+${country.dialCode}$local';
  }

  @override
  State<PetsyPhoneField> createState() => PetsyPhoneFieldState();
}

class PetsyPhoneFieldState extends State<PetsyPhoneField> {
  late PhoneCountry _country;
  late TextEditingController _controller;
  late bool _ownsController;

  PhoneCountry get country => _country;

  String get completeNumber => PetsyPhoneField.compose(_country, _controller.text);

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    final initial = widget.initialCountryIso == null
        ? detectPhoneCountry()
        : (phoneCountryByIso(widget.initialCountryIso!) ?? detectPhoneCountry());
    _country = initial;
    final seed = initial.normalizeNational(widget.initialNationalNumber ?? widget.controller?.text ?? '');
    _controller = widget.controller ?? TextEditingController(text: seed);
    if (widget.controller != null && widget.controller!.text != seed) {
      widget.controller!.text = seed;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onCountryChanged?.call(_country);
      _emit();
    });
  }

  @override
  void didUpdateWidget(covariant PetsyPhoneField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      if (_ownsController) _controller.dispose();
      _ownsController = widget.controller == null;
      _controller = widget.controller ?? TextEditingController(text: _controller.text);
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged?.call(completeNumber);

  void _onChanged(String value) {
    final normalized = _country.normalizeNational(value);
    if (normalized != value) {
      _controller.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }
    setState(() {});
    _emit();
  }

  Future<void> _pickCountry() async {
    final selected = await showModalBottomSheet<PhoneCountry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PetsyColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(PetsyRadius.xl)),
      ),
      builder: (context) => _CountryPickerSheet(selected: _country),
    );
    if (selected == null || !mounted) return;
    final normalized = selected.normalizeNational(_controller.text);
    setState(() => _country = selected);
    if (normalized != _controller.text) {
      _controller.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }
    widget.onCountryChanged?.call(selected);
    _emit();
  }

  String? _defaultValidator(String? value) {
    final digits = _country.normalizeNational(value ?? '');
    if (digits.isEmpty) {
      return widget.required ? context.t('required') : null;
    }
    if (digits.length != _country.nsnLength) {
      return context.t('phone_length').replaceAll('{n}', '${_country.nsnLength}');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.decoration ?? const InputDecoration();

    return TextFormField(
      controller: _controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      keyboardType: TextInputType.phone,
      textDirection: TextDirection.ltr,
      textInputAction: widget.textInputAction,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        _NationalPhoneFormatter(country: _country),
      ],
      onChanged: _onChanged,
      validator: widget.validator ?? _defaultValidator,
      decoration: base.copyWith(
        hintText: _country.mask,
        hintStyle: base.hintStyle ??
            TextStyle(
              color: PetsyColors.textLight.withValues(alpha: 0.85),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
        helperText: null,
        prefixIcon: _CountryPrefix(country: _country, enabled: widget.enabled, onTap: _pickCountry),
        prefixIconConstraints: const BoxConstraints(minWidth: 92, minHeight: 48),
        counterText: '${_controller.text.length}/${_country.nsnLength}',
      ),
    );
  }
}

/// Digits only, strip trunk `0`, strip pasted dial code, cap at [PhoneCountry.nsnLength].
class _NationalPhoneFormatter extends TextInputFormatter {
  _NationalPhoneFormatter({required this.country});

  final PhoneCountry country;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final normalized = country.normalizeNational(newValue.text);
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }
}

class _CountryPrefix extends StatelessWidget {
  const _CountryPrefix({required this.country, required this.enabled, required this.onTap});

  final PhoneCountry country;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return UnconstrainedBox(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 6, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CountryFlag(iso: country.iso, emoji: country.flag, size: 20),
                const SizedBox(width: 6),
                Text(
                  country.dialLabel,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: PetsyColors.primaryDark,
                    fontSize: 14,
                  ),
                ),
                Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: PetsyColors.textSecondary.withValues(alpha: 0.9),
                ),
                Container(
                  margin: const EdgeInsetsDirectional.only(start: 8),
                  width: 1,
                  height: 22,
                  color: PetsyColors.border,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet({required this.selected});

  final PhoneCountry selected;

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final _search = TextEditingController();
  late List<PhoneCountry> _filtered = List.of(kPhoneCountries);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _filter(String q) {
    setState(() {
      _filtered = kPhoneCountries.where((c) => c.matches(q)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final height = MediaQuery.sizeOf(context).height * 0.78;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: PetsyColors.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.t('select_country'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: _filter,
                decoration: InputDecoration(
                  hintText: context.t('search_country'),
                  prefixIcon: const Icon(Icons.search_rounded, color: PetsyColors.primaryDark),
                  filled: true,
                  fillColor: PetsyColors.mist,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(PetsyRadius.md),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Text(
                        context.t('no_countries'),
                        style: const TextStyle(color: PetsyColors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1, color: PetsyColors.border),
                      itemBuilder: (context, i) {
                        final c = _filtered[i];
                        final selected = c.iso == widget.selected.iso && c.dialCode == widget.selected.dialCode;
                        final name = isArabic ? c.nameAr : c.nameEn;
                        return ListTile(
                          onTap: () => Navigator.pop(context, c),
                          leading: CountryFlag(iso: c.iso, emoji: c.flag, size: 24),
                          title: Text(name, style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
                          subtitle: Text(
                            '${c.iso} · ${context.t('phone_digits').replaceAll('{n}', '${c.nsnLength}')}',
                            style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                c.dialLabel,
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(fontWeight: FontWeight.w700, color: PetsyColors.primaryDark),
                              ),
                              if (selected) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.check_circle_rounded, color: PetsyColors.primary, size: 20),
                              ],
                            ],
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
