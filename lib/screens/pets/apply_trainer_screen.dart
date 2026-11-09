import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../widgets/choice_field.dart';
import '../../widgets/city_field.dart';
import '../../widgets/common.dart';
import '../../widgets/pet_photo_picker.dart';
import '../../widgets/phone_field.dart';
import '../../data/phone_countries.dart';
import 'training_screens.dart';

/// User-facing form to apply as a trainer. Applications stay private until admin approval.
class ApplyTrainerScreen extends StatefulWidget {
  const ApplyTrainerScreen({super.key});

  @override
  State<ApplyTrainerScreen> createState() => _ApplyTrainerScreenState();
}

class _ApplyTrainerScreenState extends State<ApplyTrainerScreen> {
  final _form = GlobalKey<FormState>();
  final _phoneKey = GlobalKey<PetsyPhoneFieldState>();
  final _name = TextEditingController();
  final _title = TextEditingController();
  final _bio = TextEditingController();
  final _experience = TextEditingController(text: '1');
  final _price = TextEditingController();
  final _currency = TextEditingController(text: 'USD');
  final _city = TextEditingController();
  final _phone = TextEditingController();
  String? _image;
  String _country = 'SY';
  final Set<String> _categories = {'obedience'};
  final Set<String> _petTypes = {'dog'};
  bool _international = false;
  bool _busy = false;
  bool _loadingExisting = true;
  String? _existingStatus;
  String? _existingNotes;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    try {
      final existing = await context.api.myTrainerApplication();
      if (!mounted) return;
      if (existing != null) {
        setState(() {
          _existingStatus = existing.status;
          _existingNotes = existing.verificationNotes;
          _name.text = existing.name;
          _title.text = existing.title ?? '';
          _bio.text = existing.bio ?? '';
          _experience.text = '${existing.experienceYears}';
          if (existing.priceFrom != null) {
            _price.text = existing.priceFrom!.truncateToDouble() == existing.priceFrom
                ? existing.priceFrom!.toStringAsFixed(0)
                : '${existing.priceFrom}';
          }
          _currency.text = (existing.currency ?? 'USD').toUpperCase();
          _city.text = existing.city ?? '';
          _phone.text = parseStoredPhone(existing.phone).national;
          _image = existing.image;
          _country = trainerCountries.contains(existing.country) ? existing.country! : 'SY';
          _categories
            ..clear()
            ..addAll(existing.categories.where(trainerCategories.contains));
          if (_categories.isEmpty) _categories.add('obedience');
          _petTypes
            ..clear()
            ..addAll(existing.petTypes.where((e) => e == 'dog' || e == 'cat' || e == 'all' || e == 'other'));
          if (_petTypes.isEmpty) _petTypes.add('dog');
          _international = existing.servesInternational;
        });
      }
    } catch (_) {
      // First-time applicant.
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _title, _bio, _experience, _price, _currency, _city, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_existingStatus == 'pending_verification') {
      context.snack(context.t('trainer_apply_already_pending'), error: true);
      return;
    }
    if (_existingStatus == 'active') {
      context.snack(context.t('trainer_apply_already_approved'), error: true);
      return;
    }
    if (!_form.currentState!.validate()) return;
    if (_categories.isEmpty) {
      context.snack(context.t('trainer_apply_categories_required'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.api.applyAsTrainer({
        'name': _name.text.trim(),
        'title': _title.text.trim().isEmpty ? null : _title.text.trim(),
        'categories': _categories.toList(),
        'pet_types': _petTypes.toList(),
        'experience_years': int.tryParse(_experience.text.trim()) ?? 0,
        'phone': _phoneKey.currentState?.completeNumber ?? _phone.text.trim(),
        'city': _city.text.trim(),
        'country': _country,
        'bio': _bio.text.trim(),
        'image_url': (_image ?? '').trim().isEmpty ? null : _image!.trim(),
        'price_from': double.tryParse(_price.text.trim().replaceAll(',', '.')),
        'currency': _currency.text.trim().isEmpty ? 'USD' : _currency.text.trim().toUpperCase(),
        'serves_international': _international,
        'languages': ['ar', 'en'],
      });
      if (!mounted) return;
      context.snack(context.t('trainer_apply_submitted'), success: true, icon: Icons.hourglass_top_rounded);
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && (e.code == 'TRAINER_PENDING' || e.code == 'TRAINER_EXISTS')) {
        context.snack(context.errorText(e), error: true);
      } else {
        context.snack(context.errorText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingExisting) {
      return PetsyPage(
        appBar: AppBar(title: Text(context.t('trainer_apply_title'))),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final locked = _existingStatus == 'pending_verification' || _existingStatus == 'active';

    return PetsyPage(
      appBar: AppBar(title: Text(context.t('trainer_apply_title'))),
      child: Form(
        key: _form,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 12, PetsySpacing.page, 28),
                children: [
                  const _ApplyTrainerHero(),
                  if (_existingStatus != null) ...[
                    const SizedBox(height: 12),
                    _ApplicationStatusBanner(status: _existingStatus!, notes: _existingNotes),
                  ],
                  const SizedBox(height: 14),
                  SectionCard(
                    title: context.t('trainer_apply_photo'),
                    icon: Icons.person_outline_rounded,
                    child: PetPhotoPicker(
                      imageUrl: _image,
                      enabled: !locked && !_busy,
                      title: context.t('trainer_apply_photo'),
                      hint: context.t('trainer_apply_photo_hint'),
                      emptyIcon: Icons.person_outline_rounded,
                      onChanged: (url) => setState(() => _image = url),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: context.t('trainer_apply_section_profile'),
                    icon: Icons.badge_outlined,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _name,
                          enabled: !locked,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: context.t('name'),
                            hintText: context.t('trainer_apply_name_hint'),
                            prefixIcon: const Icon(Icons.person_outline_rounded),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? context.t('required') : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _title,
                          enabled: !locked,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: context.t('trainer_apply_title_field'),
                            hintText: context.t('trainer_apply_title_hint'),
                            prefixIcon: const Icon(Icons.workspace_premium_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _experience,
                          enabled: !locked,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            labelText: context.t('years_experience'),
                            prefixIcon: const Icon(Icons.timeline_rounded),
                          ),
                          validator: (v) {
                            final n = int.tryParse((v ?? '').trim());
                            return n == null || n < 0 ? context.t('required') : null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _bio,
                          enabled: !locked,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: context.t('bio'),
                            hintText: context.t('trainer_apply_bio_hint'),
                            alignLabelWithHint: true,
                          ),
                          validator: (v) => (v == null || v.trim().length < 20) ? context.t('trainer_apply_bio_short') : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: context.t('trainer_apply_section_skills'),
                    icon: Icons.psychology_alt_rounded,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.t('trainer_apply_categories'),
                          style: const TextStyle(fontWeight: FontWeight.w700, color: PetsyColors.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final c in trainerCategories)
                              PetsyPill(
                                style: PetsyPillStyle.choice,
                                label: context.t('trainer_cat_$c'),
                                icon: trainerCategoryIcon(c),
                                selected: _categories.contains(c),
                                onTap: locked
                                    ? () {}
                                    : () => setState(() {
                                          if (_categories.contains(c)) {
                                            if (_categories.length > 1) _categories.remove(c);
                                          } else {
                                            _categories.add(c);
                                          }
                                        }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          context.t('trainer_apply_pet_types'),
                          style: const TextStyle(fontWeight: FontWeight.w700, color: PetsyColors.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final p in const ['dog', 'cat', 'other'])
                              PetsyPill(
                                style: PetsyPillStyle.choice,
                                label: context.t(p),
                                icon: Icons.pets_outlined,
                                selected: _petTypes.contains(p),
                                onTap: locked
                                    ? () {}
                                    : () => setState(() {
                                          if (_petTypes.contains(p)) {
                                            if (_petTypes.length > 1) _petTypes.remove(p);
                                          } else {
                                            _petTypes.add(p);
                                          }
                                        }),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: context.t('trainer_apply_section_contact'),
                    icon: Icons.place_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PetsyPhoneField(
                          key: _phoneKey,
                          controller: _phone,
                          required: true,
                          enabled: !locked,
                          decoration: InputDecoration(labelText: context.t('phone')),
                        ),
                        const SizedBox(height: 12),
                        PetsyChoiceField<String>(
                          label: context.t('country_label'),
                          prefixIcon: Icons.public_rounded,
                          enabled: !locked,
                          required: true,
                          value: _country,
                          options: [
                            for (final c in trainerCountries)
                              PetsyChoiceOption(
                                        value: c,
                                        label: context.t('country_$c'),
                                        icon: Icons.flag_outlined,
                                        keywords: [c],
                                      ),
                          ],
                          onChanged: (v) => setState(() => _country = v),
                        ),
                        const SizedBox(height: 12),
                        PetsyCityField(
                          controller: _city,
                          required: true,
                          enabled: !locked,
                          autofillFromGps: _city.text.trim().isEmpty,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _price,
                                enabled: !locked,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: context.t('trainer_apply_price_from'),
                                  prefixIcon: const Icon(Icons.payments_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _currency,
                                enabled: !locked,
                                textCapitalization: TextCapitalization.characters,
                                decoration: InputDecoration(labelText: context.t('currency')),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Material(
                          color: _international ? PetsyColors.accentSoft : PetsyColors.backgroundAlt,
                          borderRadius: BorderRadius.circular(PetsyRadius.md),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(PetsyRadius.md),
                            onTap: locked ? null : () => setState(() => _international = !_international),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.public_rounded,
                                    color: _international ? PetsyColors.accent : PetsyColors.textSecondary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(context.t('training_international'), style: const TextStyle(fontWeight: FontWeight.w800)),
                                        Text(context.t('trainer_apply_intl_hint'), style: const TextStyle(fontSize: 12, color: PetsyColors.textSecondary)),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: _international,
                                    onChanged: locked ? null : (v) => setState(() => _international = v),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!locked)
              Material(
                elevation: 10,
                color: Colors.white,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 10, PetsySpacing.page, 12),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _submit,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                              )
                            : const Icon(Icons.send_rounded),
                        label: Text(context.t('trainer_apply_submit')),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ApplyTrainerHero extends StatelessWidget {
  const _ApplyTrainerHero();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(PetsyRadius.xl),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF1F4E5F), PetsyColors.accent, Color(0xFF56B8A8)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: -16,
              bottom: -22,
              child: Icon(Icons.school_rounded, size: 108, color: Colors.white.withValues(alpha: 0.12)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      context.t('trainer_apply_hero_tag'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.t('trainer_apply_hero_title'),
                    style: PetsyType.title.copyWith(color: Colors.white, fontSize: 22, height: 1.2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.t('trainer_apply_hero_body'),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13.5, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApplicationStatusBanner extends StatelessWidget {
  const _ApplicationStatusBanner({required this.status, this.notes});

  final String status;
  final String? notes;

  @override
  Widget build(BuildContext context) {
    final pending = status == 'pending_verification';
    final rejected = status == 'rejected';
    final color = pending
        ? PetsyColors.warning
        : rejected
            ? PetsyColors.error
            : PetsyColors.success;
    final title = pending
        ? context.t('trainer_apply_status_pending')
        : rejected
            ? context.t('trainer_apply_status_rejected')
            : context.t('trainer_apply_status_approved');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                pending
                    ? Icons.hourglass_top_rounded
                    : rejected
                        ? Icons.cancel_outlined
                        : Icons.verified_rounded,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color))),
            ],
          ),
          if (rejected && (notes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(notes!, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
          ],
        ],
      ),
    );
  }
}
