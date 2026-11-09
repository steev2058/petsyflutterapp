import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/petsy_logo.dart';
import '../auth/auth_screens.dart';
import '../pets/pet_screens.dart';

Future<void> _finishOnboarding(BuildContext context) async {
  await context.read<AuthState>().completeOnboarding();
  if (context.mounted) context.go('/home');
}

IconData _onboardingSpeciesIcon(String species) => switch (species) {
      'dog' => Icons.pets_rounded,
      'cat' => Icons.cruelty_free_outlined,
      'bird' => Icons.flutter_dash_rounded,
      'fish' => Icons.set_meal_outlined,
      'rabbit' => Icons.cruelty_free_rounded,
      _ => Icons.emoji_nature_rounded,
    };

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= total; i++) ...[
          if (i > 1) const SizedBox(width: PetsySpacing.sm - 2),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: i == step ? 26 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i <= step ? PetsyColors.primary : PetsyColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ],
        const SizedBox(width: PetsySpacing.sm + 2),
        Text(
          context.t('onboarding_step').replaceAll('{n}', '$step').replaceAll('{total}', '$total'),
          style: PetsyType.meta.copyWith(fontWeight: FontWeight.w700, color: PetsyColors.primaryDark, fontSize: 12.5),
        ),
      ],
    );
  }
}

/// Fades and lifts its child in after [delay], for a staggered entrance.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.child, this.delay = 0});

  final Widget child;
  final int delay;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 450 + delay),
      curve: Interval(delay / (450 + delay), 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 18), child: child),
      ),
      child: child,
    );
  }
}

class OnboardingWelcomeScreen extends StatelessWidget {
  const OnboardingWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final name = context.watch<AuthState>().user?.name;
    final greeting = (name == null || name.trim().isEmpty)
        ? context.t('onboarding_welcome')
        : '${context.t('onboarding_welcome')}، ${name.split(' ').first}';

    const perks = [
      (Icons.pets_rounded, 'onboarding_perk_pets_title', 'onboarding_perk_pets_body', PetsyColors.primary),
      (Icons.volunteer_activism_rounded, 'onboarding_perk_adopt_title', 'onboarding_perk_adopt_body', PetsyColors.accent),
      (Icons.medical_services_outlined, 'onboarding_perk_vet_title', 'onboarding_perk_vet_body', PetsyColors.secondary),
    ];

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuthAtmosphere(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const _StepIndicator(step: 1, total: 2),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _finishOnboarding(context),
                        child: Text(context.t('skip')),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(top: 8, bottom: 12),
                      children: [
                        const _Entrance(child: PetsyLogo(markSize: 88, showWordmark: true, animated: false)),
                        const SizedBox(height: 24),
                        _Entrance(
                          delay: 80,
                          child: Text(
                            greeting,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, height: 1.25),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _Entrance(
                          delay: 140,
                          child: Text(
                            context.t('onboarding_welcome_support'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: PetsyColors.textSecondary, height: 1.45, fontSize: 14.5),
                          ),
                        ),
                        const SizedBox(height: 26),
                        for (var i = 0; i < perks.length; i++)
                          _Entrance(
                            delay: 220 + i * 110,
                            child: _OnboardingPerk(
                              icon: perks[i].$1,
                              titleKey: perks[i].$2,
                              bodyKey: perks[i].$3,
                              color: perks[i].$4,
                            ),
                          ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => context.push('/onboarding/pet'),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(context.t('onboarding_add_pet_cta')),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => _finishOnboarding(context),
                    child: Text(context.t('onboarding_skip_pet')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPerk extends StatelessWidget {
  const _OnboardingPerk({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
    required this.color,
  });

  final IconData icon;
  final String titleKey;
  final String bodyKey;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PetsyColors.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(PetsyRadius.lg),
          border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withValues(alpha: 0.85), color],
                ),
                borderRadius: BorderRadius.circular(PetsyRadius.md),
              ),
              child: Icon(icon, color: Colors.white, size: 23),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t(titleKey),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.t(bodyKey),
                    style: const TextStyle(color: PetsyColors.textSecondary, height: 1.35, fontSize: 13),
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

class OnboardingAddPetScreen extends StatefulWidget {
  const OnboardingAddPetScreen({super.key});

  @override
  State<OnboardingAddPetScreen> createState() => _OnboardingAddPetScreenState();
}

class _OnboardingAddPetScreenState extends State<OnboardingAddPetScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  String _species = 'cat';
  String _gender = 'male';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final pet = await context.api.createPet({
        'name': _name.text.trim(),
        'species': _species,
        'gender': _gender,
        'status': 'owned',
      });
      if (!mounted) return;
      context.snack(context.t('pet_added'));
      context.go('/edit-pet/${pet.id}?onboarding=1');
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuthAtmosphere(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 12, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => context.canPop() ? context.pop() : context.go('/onboarding'),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: PetsyColors.primaryDark),
                      ),
                      const _StepIndicator(step: 2, total: 2),
                      const Spacer(),
                      TextButton(
                        onPressed: _busy ? null : () => _finishOnboarding(context),
                        child: Text(context.t('skip')),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Entrance(
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                                child: Container(
                                  key: ValueKey(_species),
                                  width: 84,
                                  height: 84,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [PetsyColors.secondary, PetsyColors.primary],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: PetsyColors.primary.withValues(alpha: 0.3),
                                        blurRadius: 20,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Icon(_onboardingSpeciesIcon(_species), color: Colors.white, size: 40),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _Entrance(
                            delay: 80,
                            child: Text(
                              context.t('onboarding_pet_title'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _Entrance(
                            delay: 120,
                            child: Text(
                              context.t('onboarding_pet_support'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: PetsyColors.textSecondary, height: 1.4),
                            ),
                          ),
                          const SizedBox(height: 22),
                          _Entrance(
                            delay: 200,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                              decoration: BoxDecoration(
                                color: PetsyColors.surface.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(PetsyRadius.xl),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
                                boxShadow: [
                                  BoxShadow(
                                    color: PetsyColors.primaryDark.withValues(alpha: 0.06),
                                    blurRadius: 24,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextFormField(
                                    controller: _name,
                                    textInputAction: TextInputAction.done,
                                    decoration: InputDecoration(
                                      labelText: context.t('pet_name'),
                                      prefixIcon: const Icon(Icons.badge_outlined, color: PetsyColors.primaryDark),
                                      filled: true,
                                      fillColor: PetsyColors.surface.withValues(alpha: 0.95),
                                    ),
                                    validator: (v) => (v == null || v.trim().isEmpty) ? context.t('required') : null,
                                    onFieldSubmitted: (_) => _submit(),
                                  ),
                                  const SizedBox(height: 18),
                                  _label(context.t('species')),
                                  GridView.count(
                                    crossAxisCount: 3,
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                    childAspectRatio: 1.15,
                                    children: [
                                      for (final s in petSpecies)
                                        _ChoiceTile(
                                          icon: _onboardingSpeciesIcon(s),
                                          label: context.t(s),
                                          selected: _species == s,
                                          onTap: () => setState(() => _species = s),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  _label(context.t('gender')),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _ChoiceTile(
                                          icon: Icons.male_rounded,
                                          label: context.t('male'),
                                          selected: _gender == 'male',
                                          horizontal: true,
                                          onTap: () => setState(() => _gender = 'male'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _ChoiceTile(
                                          icon: Icons.female_rounded,
                                          label: context.t('female'),
                                          selected: _gender == 'female',
                                          horizontal: true,
                                          onTap: () => setState(() => _gender = 'female'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 22),
                                  SubmitButton(
                                    label: context.t('onboarding_save_pet'),
                                    busy: _busy,
                                    onPressed: _submit,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    context.t('onboarding_pet_more_later'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
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
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.horizontal = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? PetsyColors.primaryDark : PetsyColors.textSecondary;
    final children = [
      Icon(icon, color: selected ? PetsyColors.primary : PetsyColors.textLight, size: horizontal ? 22 : 26),
      SizedBox(width: horizontal ? 8 : 0, height: horizontal ? 0 : 6),
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: selected ? PetsyColors.text : fg),
        ),
      ),
    ];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? PetsyColors.primarySoft : PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.md),
        border: Border.all(color: selected ? PetsyColors.primary : PetsyColors.border, width: selected ? 1.6 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: horizontal ? 14 : 8),
            child: horizontal
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: children)
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: children),
          ),
        ),
      ),
    );
  }
}
