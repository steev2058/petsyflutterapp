import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/choice_field.dart';
import '../../widgets/city_field.dart';
import '../../widgets/common.dart';
import '../../widgets/pet_photo_picker.dart';
import 'guard_dogs_screen.dart';

/// Dedicated marketplace form for publishing a professional guard-dog listing.
/// Separate from the general “Add pet” flow.
class AddGuardOfferScreen extends StatefulWidget {
  const AddGuardOfferScreen({super.key});

  @override
  State<AddGuardOfferScreen> createState() => _AddGuardOfferScreenState();
}

class _AddGuardOfferScreenState extends State<AddGuardOfferScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _breed = TextEditingController();
  final _age = TextEditingController();
  final _color = TextEditingController();
  final _weight = TextEditingController();
  final _location = TextEditingController();
  final _price = TextEditingController();
  final _currency = TextEditingController(text: 'SYP');
  final _description = TextEditingController();
  String? _image;
  String _gender = 'male';
  bool _ageMonths = false;
  String _guardRole = 'home';
  String _sellerType = 'individual';
  String _country = 'SY';
  bool _vaccinated = true;
  bool _neutered = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _breed, _age, _color, _weight, _location, _price, _currency, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _ageStored() {
    final raw = _age.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    final n = num.tryParse(raw);
    if (n == null) return null;
    return PetAge(n, months: _ageMonths).stored;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.api.createPet({
        'name': _name.text.trim(),
        'species': 'dog',
        'gender': _gender,
        'status': 'for_sale',
        'purpose': 'guard',
        'breed': _breed.text.trim().isEmpty ? null : _breed.text.trim(),
        'age': _ageStored(),
        'color': _color.text.trim().isEmpty ? null : _color.text.trim(),
        'weight': double.tryParse(_weight.text.trim().replaceAll(',', '.')),
        'location': _location.text.trim().isEmpty ? null : _location.text.trim(),
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
        'image': (_image ?? '').trim().isEmpty ? null : _image!.trim(),
        'price': double.parse(_price.text.trim().replaceAll(',', '.')),
        'currency': _currency.text.trim().isEmpty ? 'SYP' : _currency.text.trim().toUpperCase(),
        'guard_role': _guardRole,
        'country': _country,
        'seller_type': _sellerType,
        'vaccinated': _vaccinated,
        'neutered': _neutered,
      });
      if (!mounted) return;
      context.snack(context.t('guard_offer_published'), success: true, icon: Icons.security_rounded);
      context.pop(true);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PetsyPage(
      appBar: AppBar(title: Text(context.t('add_guard_dog'))),
      child: Form(
        key: _form,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 12, PetsySpacing.page, 28),
                children: [
                  const _GuardOfferHero(),
                  const SizedBox(height: 14),
                  SectionCard(
                    title: context.t('pet_photo'),
                    icon: Icons.photo_camera_outlined,
                    child: PetPhotoPicker(
                      imageUrl: _image,
                      enabled: !_busy,
                      onChanged: (url) => setState(() => _image = url),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: context.t('guard_offer_section_dog'),
                    icon: Icons.pets_rounded,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _name,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: context.t('pet_name'),
                            hintText: context.t('guard_offer_name_hint'),
                            prefixIcon: const Icon(Icons.badge_outlined),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? context.t('required') : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _breed,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: context.t('breed'),
                            hintText: context.t('guard_offer_breed_hint'),
                            prefixIcon: const Icon(Icons.category_outlined),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? context.t('required') : null,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          context.t('gender'),
                          style: const TextStyle(color: PetsyColors.textSecondary, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _GuardChoiceTile(
                                label: context.t('male'),
                                icon: Icons.male_rounded,
                                color: PetsyColors.genderMale,
                                selected: _gender == 'male',
                                onTap: () => setState(() => _gender = 'male'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _GuardChoiceTile(
                                label: context.t('female'),
                                icon: Icons.female_rounded,
                                color: PetsyColors.genderFemale,
                                selected: _gender == 'female',
                                onTap: () => setState(() => _gender = 'female'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _age,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                                decoration: InputDecoration(
                                  labelText: context.t('age'),
                                  hintText: context.t('pet_age_hint'),
                                  prefixIcon: const Icon(Icons.cake_outlined),
                                ),
                                validator: (v) {
                                  final raw = v?.trim().replaceAll(',', '.') ?? '';
                                  if (raw.isEmpty) return context.t('required');
                                  final n = num.tryParse(raw);
                                  return n == null || n <= 0 || n > 100 ? context.t('age_invalid') : null;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                children: [
                                  PetsyPill(
                                    style: PetsyPillStyle.choice,
                                    label: context.t('age_unit_years'),
                                    selected: !_ageMonths,
                                    onTap: () => setState(() => _ageMonths = false),
                                  ),
                                  const SizedBox(width: 6),
                                  PetsyPill(
                                    style: PetsyPillStyle.choice,
                                    label: context.t('age_unit_months'),
                                    selected: _ageMonths,
                                    onTap: () => setState(() => _ageMonths = true),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _color,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: context.t('color'),
                                  prefixIcon: const Icon(Icons.palette_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _weight,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: context.t('weight'),
                                  prefixIcon: const Icon(Icons.monitor_weight_outlined),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: context.t('guard_offer_section_listing'),
                    icon: Icons.storefront_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PetsyChoiceField<String>(
                          label: context.t('guard_role_label'),
                          prefixIcon: Icons.security_rounded,
                          required: true,
                          value: _guardRole,
                          options: [
                            for (final role in guardRoles)
                              PetsyChoiceOption(
                                value: role,
                                label: context.t('guard_role_$role'),
                                icon: guardRoleIcon(role),
                              ),
                          ],
                          onChanged: (v) => setState(() => _guardRole = v),
                        ),
                        const SizedBox(height: 12),
                        PetsyChoiceField<String>(
                          label: context.t('seller_type_label'),
                          prefixIcon: Icons.storefront_outlined,
                          required: true,
                          value: _sellerType,
                          options: [
                            for (final s in sellerTypes)
                              PetsyChoiceOption(
                                value: s,
                                label: context.t('seller_$s'),
                                icon: Icons.badge_outlined,
                              ),
                          ],
                          onChanged: (v) => setState(() => _sellerType = v),
                        ),
                        const SizedBox(height: 12),
                        PetsyChoiceField<String>(
                          label: context.t('country_label'),
                          prefixIcon: Icons.public_rounded,
                          required: true,
                          value: _country,
                          options: [
                            for (final c in guardCountries)
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
                          controller: _location,
                          label: context.t('city'),
                          required: true,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _price,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                                decoration: InputDecoration(
                                  labelText: context.t('price'),
                                  prefixIcon: const Icon(Icons.payments_outlined),
                                ),
                                validator: (v) {
                                  final n = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                                  return n == null || n <= 0 ? context.t('required') : null;
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _currency,
                                textCapitalization: TextCapitalization.characters,
                                decoration: InputDecoration(
                                  labelText: context.t('currency'),
                                  hintText: 'SYP',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: context.t('pet_form_health'),
                    icon: Icons.health_and_safety_outlined,
                    child: Column(
                      children: [
                        _GuardHealthToggle(
                          icon: Icons.vaccines_outlined,
                          title: context.t('vaccinated'),
                          subtitle: context.t('pet_vaccinated_hint'),
                          value: _vaccinated,
                          onChanged: (v) => setState(() => _vaccinated = v),
                        ),
                        const SizedBox(height: 8),
                        _GuardHealthToggle(
                          icon: Icons.verified_user_outlined,
                          title: context.t('neutered'),
                          subtitle: context.t('pet_neutered_hint'),
                          value: _neutered,
                          onChanged: (v) => setState(() => _neutered = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: context.t('guard_offer_section_about'),
                    icon: Icons.notes_rounded,
                    child: TextFormField(
                      controller: _description,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: context.t('guard_offer_desc_hint'),
                        alignLabelWithHint: true,
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(bottom: 54),
                          child: Icon(Icons.edit_note_rounded),
                        ),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? context.t('required') : null,
                    ),
                  ),
                ],
              ),
            ),
            _GuardOfferSaveBar(busy: _busy, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

class _GuardOfferHero extends StatelessWidget {
  const _GuardOfferHero();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(PetsyRadius.xl),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF1A2330), Color(0xFF2F4A5C), PetsyColors.accent],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: -18,
              bottom: -24,
              child: Icon(Icons.security_rounded, size: 110, color: Color(0x22FFFFFF)),
            ),
            Positioned(
              right: -12,
              top: -16,
              child: Icon(Icons.pets_rounded, size: 84, color: Color(0x1AFFFFFF)),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: _GuardOfferHeroText(),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuardOfferHeroText extends StatelessWidget {
  const _GuardOfferHeroText();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Text(
            context.t('guard_offer_hero_tag'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          context.t('guard_offer_hero_title'),
          style: PetsyType.title.copyWith(color: Colors.white, fontSize: 22, height: 1.2),
        ),
        const SizedBox(height: 6),
        Text(
          context.t('guard_offer_hero_body'),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13.5, height: 1.4),
        ),
      ],
    );
  }
}

class _GuardHealthToggle extends StatelessWidget {
  const _GuardHealthToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: value ? PetsyColors.accentSoft : PetsyColors.backgroundAlt,
      borderRadius: BorderRadius.circular(PetsyRadius.md),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(PetsyRadius.md),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          child: Row(
            children: [
              Icon(icon, color: value ? PetsyColors.accent : PetsyColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(subtitle, style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuardChoiceTile extends StatelessWidget {
  const _GuardChoiceTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PetsyPressScale(
      onTap: onTap,
      scale: 0.97,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 50,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : PetsyColors.backgroundAlt,
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          border: Border.all(color: selected ? color : PetsyColors.border, width: selected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? color : PetsyColors.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? color : PetsyColors.text)),
          ],
        ),
      ),
    );
  }
}

class _GuardOfferSaveBar extends StatelessWidget {
  const _GuardOfferSaveBar({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      color: Colors.white,
      shadowColor: PetsyColors.ink.withValues(alpha: 0.12),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 10, PetsySpacing.page, 12),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: busy ? null : onPressed,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Icon(Icons.publish_rounded, size: 20),
              label: Text(context.t('guard_offer_publish')),
            ),
          ),
        ),
      ),
    );
  }
}
