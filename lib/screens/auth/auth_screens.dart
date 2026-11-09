import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/petsy_logo.dart';
import '../../widgets/phone_field.dart';
import '../../widgets/social_auth.dart';

/// Prefill for local/debug testing so login is one tap.
const _debugLoginEmail = 'mustafa.joha001@gmail.com';
const _debugLoginPassword = '123456';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? _requiredValidator(BuildContext context, String? v) =>
    (v == null || v.trim().isEmpty) ? context.t('required') : null;

String? _emailValidator(BuildContext context, String? v) =>
    _emailPattern.hasMatch(v?.trim() ?? '') ? null : context.t('invalid_email');

String? _passwordValidator(BuildContext context, String? v) =>
    (v ?? '').length < 6 ? context.t('password_min') : null;

InputDecoration _authFieldDecoration({required String label, required IconData icon, Widget? suffix}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: PetsyColors.primaryDark.withValues(alpha: 0.75)),
    suffixIcon: suffix,
    filled: true,
    fillColor: PetsyColors.surface.withValues(alpha: 0.92),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(PetsyRadius.md), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(PetsyRadius.md),
      borderSide: BorderSide(color: PetsyColors.border.withValues(alpha: 0.7)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(PetsyRadius.md),
      borderSide: const BorderSide(color: PetsyColors.primary, width: 1.6),
    ),
  );
}

class SubmitButton extends StatelessWidget {
  const SubmitButton({super.key, required this.label, required this.busy, required this.onPressed});

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
          : Text(label),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  static const _minShow = Duration(milliseconds: 2200);

  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  late final AnimationController _breath =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat(reverse: true);

  late final Animation<double> _fade = CurvedAnimation(parent: _intro, curve: Curves.easeOut);
  late final Animation<Offset> _rise = Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(
    CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _halo = Tween(begin: 0.82, end: 1.0).animate(
    CurvedAnimation(parent: _breath, curve: Curves.easeInOut),
  );

  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _intro.dispose();
    _breath.dispose();
    super.dispose();
  }

  Future<void> _waitReady(AuthState auth) async {
    if (auth.isReady) return;
    final done = Completer<void>();
    void listener() {
      if (auth.isReady && !done.isCompleted) done.complete();
    }

    auth.addListener(listener);
    try {
      await done.future;
    } finally {
      auth.removeListener(listener);
    }
  }

  Future<void> _boot() async {
    final auth = context.read<AuthState>();
    final started = DateTime.now();
    await _waitReady(auth);
    final left = _minShow - DateTime.now().difference(started);
    if (left > Duration.zero) await Future<void>.delayed(left);
    if (!mounted || _leaving) return;
    _leaving = true;
    context.go(auth.isLoggedIn ? '/home' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuthAtmosphere(),
          SafeArea(
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _rise,
                child: Column(
                  children: [
                    const Spacer(flex: 3),
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        ScaleTransition(
                          scale: _halo,
                          child: IgnorePointer(
                            child: Container(
                              width: 240,
                              height: 240,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    PetsyColors.primary.withValues(alpha: 0.28),
                                    PetsyColors.primary.withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        PetsyLogo(
                          markSize: 120,
                          showWordmark: true,
                          showTagline: true,
                          tagline: context.t('app_tagline'),
                          animated: true,
                          hero: true,
                        ),
                      ],
                    ),
                    const Spacer(flex: 2),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 36),
                      child: Column(
                        children: [
                          SizedBox(
                            width: 132,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                minHeight: 3.5,
                                backgroundColor: PetsyColors.primary.withValues(alpha: 0.14),
                                color: PetsyColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Petsy',
                            style: TextStyle(
                              color: PetsyColors.primaryDark.withValues(alpha: 0.55),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(
    text: kDebugMode ? _debugLoginEmail : '',
  );
  final _password = TextEditingController(
    text: kDebugMode ? _debugLoginPassword : '',
  );
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<AuthState>().login(_email.text.trim(), _password.text);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthPageShell(
      animateLogo: true,
      panel: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AuthPanelHeader(
            title: context.t('login_headline'),
            support: context.t('login_support'),
          ),
          Form(
            key: _form,
            child: Column(
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  textInputAction: TextInputAction.next,
                  decoration: _authFieldDecoration(
                    label: context.t('email'),
                    icon: Icons.mail_outline_rounded,
                  ),
                  validator: (v) => _emailValidator(context, v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  decoration: _authFieldDecoration(
                    label: context.t('password'),
                    icon: Icons.lock_outline_rounded,
                    suffix: _AuthEyeButton(
                      obscure: _obscure,
                      onTap: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => _requiredValidator(context, v),
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => context.push('/forgot-password'),
              style: TextButton.styleFrom(foregroundColor: PetsyColors.primaryDark),
              child: Text(context.t('forgot_password')),
            ),
          ),
          SubmitButton(label: context.t('login'), busy: _busy, onPressed: _submit),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => context.go('/home'),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.55),
              side: BorderSide(color: PetsyColors.primary.withValues(alpha: 0.5)),
            ),
            child: Text(context.t('continue_guest')),
          ),
          const SizedBox(height: 16),
          const SocialAuthSection(compact: true),
        ],
      ),
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(context.t('no_account'), style: const TextStyle(color: PetsyColors.textSecondary)),
          TextButton(
            onPressed: () => context.push('/signup'),
            child: Text(context.t('signup'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.language_rounded, size: 18, color: PetsyColors.primaryDark),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: PetsyColors.primaryDark)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthChipButton extends StatelessWidget {
  const _AuthChipButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: PetsyColors.primaryDark, size: 20),
        ),
      ),
    );
  }
}

class _AuthEyeButton extends StatelessWidget {
  const _AuthEyeButton({required this.obscure, required this.onTap});

  final bool obscure;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(
        obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: PetsyColors.textSecondary,
      ),
    );
  }
}

/// Six digit boxes over a single invisible field, so paste and SMS autofill still work.
class _OtpField extends StatefulWidget {
  const _OtpField({required this.controller, this.onCompleted});

  static const length = 6;

  final TextEditingController controller;
  final VoidCallback? onCompleted;

  @override
  State<_OtpField> createState() => _OtpFieldState();
}

class _OtpFieldState extends State<_OtpField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      validator: (_) => widget.controller.text.trim().length == _OtpField.length ? null : context.t('otp_incomplete'),
      builder: (field) {
        final code = widget.controller.text;
        final focused = _focus.hasFocus;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: Stack(
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < _OtpField.length; i++) ...[
                        if (i > 0) SizedBox(width: i == _OtpField.length ~/ 2 ? 14 : 8),
                        Expanded(
                          child: _OtpBox(
                            digit: i < code.length ? code[i] : '',
                            active: focused && (i == code.length || (i == _OtpField.length - 1 && code.length == _OtpField.length)),
                            error: field.hasError,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0,
                      child: TextField(
                        controller: widget.controller,
                        focusNode: _focus,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        maxLength: _OtpField.length,
                        showCursor: false,
                        enableInteractiveSelection: false,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                        onChanged: (v) {
                          field.didChange(v);
                          if (v.length == _OtpField.length) {
                            FocusScope.of(context).unfocus();
                            widget.onCompleted?.call();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (field.hasError) ...[
              const SizedBox(height: 8),
              Text(
                field.errorText!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: PetsyColors.error, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({required this.digit, required this.active, required this.error});

  final String digit;
  final bool active;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final filled = digit.isNotEmpty;
    final borderColor = error
        ? PetsyColors.error
        : active
            ? PetsyColors.primary
            : filled
                ? PetsyColors.primary.withValues(alpha: 0.45)
                : PetsyColors.border;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? PetsyColors.primarySoft.withValues(alpha: 0.6) : PetsyColors.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(PetsyRadius.md),
        border: Border.all(color: borderColor, width: active ? 2 : 1.2),
        boxShadow: active
            ? [BoxShadow(color: PetsyColors.primary.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 3))]
            : null,
      ),
      child: Text(
        digit,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: PetsyColors.text),
      ),
    );
  }
}

/// Resend link that locks itself for a cooldown after each send.
class _ResendButton extends StatefulWidget {
  const _ResendButton({required this.onResend, this.enabled = true});

  final Future<bool> Function() onResend;
  final bool enabled;

  @override
  State<_ResendButton> createState() => _ResendButtonState();
}

class _ResendButtonState extends State<_ResendButton> {
  static const _cooldown = 60;

  Timer? _timer;
  int _left = _cooldown;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    setState(() => _left = _cooldown);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    setState(() => _sending = true);
    final ok = await widget.onResend();
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) _start();
  }

  @override
  Widget build(BuildContext context) {
    if (_left > 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.timer_outlined, size: 16, color: PetsyColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              context.t('resend_in').replaceAll('{s}', '$_left'),
              style: const TextStyle(color: PetsyColors.textSecondary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    return TextButton.icon(
      onPressed: !widget.enabled || _sending ? null : _resend,
      icon: _sending
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.refresh_rounded, size: 18),
      label: Text(context.t('resend_code')),
    );
  }
}

class _PasswordStrength extends StatelessWidget {
  const _PasswordStrength({required this.controller});

  final TextEditingController controller;

  static int _score(String p) {
    if (p.isEmpty) return 0;
    var score = 0;
    if (p.length >= 6) score++;
    if (p.length >= 10) score++;
    if (RegExp(r'\d').hasMatch(p) && RegExp(r'[A-Za-z\u0600-\u06FF]').hasMatch(p)) score++;
    if (RegExp(r'[^A-Za-z0-9\u0600-\u06FF]').hasMatch(p) || (RegExp(r'[a-z]').hasMatch(p) && RegExp(r'[A-Z]').hasMatch(p))) {
      score++;
    }
    return score.clamp(1, 4);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final text = value.text;
        if (text.isEmpty) return const SizedBox.shrink();
        final score = text.length < 6 ? 1 : _score(text);
        final (color, label) = switch (score) {
          1 => (PetsyColors.error, context.t('pw_weak')),
          2 => (PetsyColors.warning, context.t('pw_fair')),
          3 => (PetsyColors.success, context.t('pw_good')),
          _ => (PetsyColors.success, context.t('pw_strong')),
        };
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 5),
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 5,
                        decoration: BoxDecoration(
                          color: i < score ? color : PetsyColors.border,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
                  if (score < 3) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.t('pw_hint'),
                        maxLines: 2,
                        style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 11.5),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AuthIconBadge extends StatelessWidget {
  const _AuthIconBadge(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [PetsyColors.secondary, PetsyColors.primary],
          ),
          boxShadow: [
            BoxShadow(color: PetsyColors.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 30),
      ),
    );
  }
}

class _AuthPanelHeader extends StatelessWidget {
  const _AuthPanelHeader({required this.title, required this.support, this.leading});

  final String title;
  final String support;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (leading != null) ...[leading!, const SizedBox(height: 14)],
        Text(
          title,
          textAlign: TextAlign.center,
          style: PetsyType.section.copyWith(fontSize: 18),
        ),
        const SizedBox(height: PetsySpacing.sm - 2),
        Text(
          support,
          textAlign: TextAlign.center,
          style: PetsyType.subtitle.copyWith(height: 1.4),
        ),
        const SizedBox(height: PetsySpacing.lg + 2),
      ],
    );
  }
}

class _AuthGlassPanel extends StatelessWidget {
  const _AuthGlassPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      decoration: BoxDecoration(
        color: PetsyColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(PetsyRadius.xl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
        boxShadow: PetsyShadows.soft,
      ),
      child: child,
    );
  }
}

/// Shared chrome for login / signup / forgot — same spacing, logo, halo, no entrance thrash.
class _AuthPageShell extends StatefulWidget {
  const _AuthPageShell({
    required this.panel,
    this.footer,
    this.onBack,
    this.animateLogo = false,
  });

  final Widget panel;
  final Widget? footer;
  final VoidCallback? onBack;
  final bool animateLogo;

  @override
  State<_AuthPageShell> createState() => _AuthPageShellState();
}

class _AuthPageShellState extends State<_AuthPageShell> with SingleTickerProviderStateMixin {
  late final AnimationController _breath =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))..repeat(reverse: true);
  late final Animation<double> _halo = Tween(begin: 0.86, end: 1.0).animate(
    CurvedAnimation(parent: _breath, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: AuthAtmosphere()),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(22, 6, 22, 0),
                      child: SizedBox(
                        height: 40,
                        child: Row(
                          children: [
                            if (widget.onBack != null)
                              _AuthChipButton(icon: Icons.arrow_back_ios_new_rounded, onTap: widget.onBack!)
                            else
                              const SizedBox(width: 40),
                            const Spacer(),
                            _LanguageToggle(
                              label: context.t(isArabic ? 'english' : 'arabic'),
                              onTap: context.read<LocaleState>().toggle,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsetsDirectional.fromSTEB(22, PetsySpacing.md, 22, PetsySpacing.listBottom),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.topCenter,
                              children: [
                                Positioned(
                                  top: -14,
                                  child: ScaleTransition(
                                    scale: _halo,
                                    child: IgnorePointer(
                                      child: Container(
                                        width: 188,
                                        height: 188,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: RadialGradient(
                                            colors: [
                                              PetsyColors.primary.withValues(alpha: 0.24),
                                              PetsyColors.primary.withValues(alpha: 0.0),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                PetsyLogo(
                                  markSize: 112,
                                  showWordmark: true,
                                  animated: widget.animateLogo,
                                ),
                              ],
                            ),
                            const SizedBox(height: PetsySpacing.section + 2),
                            _AuthGlassPanel(child: widget.panel),
                            if (widget.footer != null) ...[
                              const SizedBox(height: PetsySpacing.page),
                              widget.footer!,
                            ],
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
    );
  }
}

/// Soft stone light, coral haze, calm teal balance, and faint paws for auth screens.
class AuthAtmosphere extends StatefulWidget {
  const AuthAtmosphere({super.key});

  @override
  State<AuthAtmosphere> createState() => _AuthAtmosphereState();
}

class _AuthAtmosphereState extends State<AuthAtmosphere> with SingleTickerProviderStateMixin {
  late final AnimationController _drift =
      AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat(reverse: true);

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _drift,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_drift.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    PetsyColors.authTop,
                    Color(0xFFFFF6F0),
                    PetsyColors.authMid,
                    PetsyColors.authBottom,
                  ],
                  stops: [0, 0.28, 0.62, 1],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1 + t * 0.2, -0.8),
                  end: Alignment(0.9, 1.1 - t * 0.12),
                  colors: [
                    PetsyColors.orbRose.withValues(alpha: 0.22),
                    Colors.transparent,
                    PetsyColors.accent.withValues(alpha: 0.08),
                    PetsyColors.primary.withValues(alpha: 0.10),
                  ],
                  stops: const [0, 0.38, 0.72, 1],
                ),
              ),
            ),
            CustomPaint(painter: _OrbPainter(progress: t)),
            CustomPaint(painter: _PawWashPainter(progress: t)),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [
                    Colors.white.withValues(alpha: 0.42),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [
                    PetsyColors.primaryDark.withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    void orb(Offset c, double r, Color color) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, paint);
    }

    final dx = (progress - 0.5) * size.width * 0.05;
    final dy = (progress - 0.5) * size.height * 0.035;

    orb(Offset(size.width * 0.86 + dx, size.height * 0.08 - dy), size.width * 0.52, PetsyColors.orbPeach.withValues(alpha: 0.38));
    orb(Offset(size.width * 0.06 - dx, size.height * 0.28 + dy), size.width * 0.40, PetsyColors.primary.withValues(alpha: 0.14));
    orb(Offset(size.width * 0.72 + dx * 0.4, size.height * 0.72 + dy), size.width * 0.46, PetsyColors.orbRose.withValues(alpha: 0.20));
    orb(Offset(size.width * 0.20 - dx * 0.35, size.height * 0.86 - dy), size.width * 0.36, PetsyColors.accent.withValues(alpha: 0.10));
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) => oldDelegate.progress != progress;
}

class _PawWashPainter extends CustomPainter {
  _PawWashPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    void paw(Offset c, double s, double opacity, double angleDeg) {
      final paint = Paint()..color = PetsyColors.primaryDark.withValues(alpha: opacity);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(angleDeg * 3.1415926535 / 180);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: s * 1.05, height: s * 0.78), paint);
      canvas.drawCircle(Offset(-s * 0.42, -s * 0.54), s * 0.24, paint);
      canvas.drawCircle(Offset(0, -s * 0.68), s * 0.26, paint);
      canvas.drawCircle(Offset(s * 0.42, -s * 0.54), s * 0.24, paint);
      canvas.restore();
    }

    final drift = (progress - 0.5) * 8;
    paw(Offset(size.width * 0.08, size.height * 0.18 + drift), 40, 0.035, -18);
    paw(Offset(size.width * 0.92, size.height * 0.30 - drift), 54, 0.045, 14);
    paw(Offset(size.width * 0.84, size.height * 0.78 + drift * 0.5), 46, 0.04, -8);
    paw(Offset(size.width * 0.12, size.height * 0.82 - drift * 0.4), 32, 0.03, 22);
  }

  @override
  bool shouldRepaint(covariant _PawWashPainter oldDelegate) => oldDelegate.progress != progress;
}

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _form = GlobalKey<FormState>();
  final _phoneKey = GlobalKey<PetsyPhoneFieldState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final result = await context.api.signup(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        phone: _phoneKey.currentState?.completeNumber ?? _phone.text.trim(),
      );
      if (!mounted) return;
      context.pushReplacement('/verify',
          extra: VerifyArgs(email: _email.text.trim(), userId: result.userId, devCode: result.devCode));
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goLogin() => context.canPop() ? context.pop() : context.go('/login');

  @override
  Widget build(BuildContext context) {
    return _AuthPageShell(
      onBack: _goLogin,
      panel: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AuthPanelHeader(
            title: context.t('signup_headline'),
            support: context.t('signup_support'),
          ),
          Form(
            key: _form,
            child: Column(
              children: [
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: _authFieldDecoration(
                    label: context.t('name'),
                    icon: Icons.person_outline_rounded,
                  ),
                  validator: (v) => _requiredValidator(context, v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  textInputAction: TextInputAction.next,
                  decoration: _authFieldDecoration(
                    label: context.t('email'),
                    icon: Icons.mail_outline_rounded,
                  ),
                  validator: (v) => _emailValidator(context, v),
                ),
                const SizedBox(height: 12),
                PetsyPhoneField(
                  key: _phoneKey,
                  controller: _phone,
                  textInputAction: TextInputAction.next,
                  decoration: _authFieldDecoration(
                    label: context.t('phone'),
                    icon: Icons.phone_outlined,
                  ).copyWith(prefixIcon: null),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.next,
                  decoration: _authFieldDecoration(
                    label: context.t('password'),
                    icon: Icons.lock_outline_rounded,
                    suffix: _AuthEyeButton(
                      obscure: _obscure,
                      onTap: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => _passwordValidator(context, v),
                ),
                _PasswordStrength(controller: _password),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirm,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  decoration: _authFieldDecoration(
                    label: context.t('confirm_password'),
                    icon: Icons.lock_person_outlined,
                    suffix: _AuthEyeButton(
                      obscure: _obscureConfirm,
                      onTap: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) {
                    if (v != _password.text) return context.t('passwords_mismatch');
                    return _passwordValidator(context, v);
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SubmitButton(label: context.t('signup'), busy: _busy, onPressed: _submit),
          const SizedBox(height: 16),
          const SocialAuthSection(compact: true),
        ],
      ),
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(context.t('have_account'), style: const TextStyle(color: PetsyColors.textSecondary)),
          TextButton(
            onPressed: _goLogin,
            child: Text(context.t('login'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class VerifyArgs {
  VerifyArgs({required this.email, required this.userId, this.devCode});

  final String email;
  final String userId;

  /// Only returned by servers running with insecure dev auth codes enabled.
  final String? devCode;
}

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key, required this.args});

  final VerifyArgs args;

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final _form = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.args.devCode);
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final auth = context.read<AuthState>();
      await auth.verify(widget.args.userId, _code.text.trim());
      if (!mounted) return;
      context.go(auth.needsOnboarding ? '/onboarding' : '/home');
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _resend() async {
    try {
      await context.api.resendVerification(widget.args.email);
      if (mounted) context.snack(context.t('code_sent'));
      return true;
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthPageShell(
      onBack: () => context.canPop() ? context.pop() : context.go('/signup'),
      panel: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AuthPanelHeader(
            leading: const _AuthIconBadge(Icons.mark_email_unread_outlined),
            title: context.t('verify_account'),
            support: context.t('verify_hint'),
          ),
          _EmailChip(email: widget.args.email),
          const SizedBox(height: 18),
          Form(
            key: _form,
            child: _OtpField(controller: _code, onCompleted: _busy ? null : _submit),
          ),
          const SizedBox(height: 20),
          SubmitButton(label: context.t('submit'), busy: _busy, onPressed: _submit),
          const SizedBox(height: 4),
          _ResendButton(onResend: _resend, enabled: !_busy),
        ],
      ),
    );
  }
}

class _EmailChip extends StatelessWidget {
  const _EmailChip({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: PetsyColors.primarySoft,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.alternate_email_rounded, size: 16, color: PetsyColors.primaryDark),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                email,
                textDirection: TextDirection.ltr,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, color: PetsyColors.primaryDark, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  bool _obscure = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sendCode() {
    if (!_form.currentState!.validate()) return;
    _run(() async {
      await context.api.forgotPassword(_email.text.trim());
      if (!mounted) return;
      setState(() => _codeSent = true);
      context.snack(context.t('code_sent'));
    });
  }

  void _reset() {
    if (!_form.currentState!.validate()) return;
    _run(() async {
      await context.api.resetPassword(_email.text.trim(), _code.text.trim(), _password.text);
      if (!mounted) return;
      context.snack(context.t('password_reset_done'));
      context.canPop() ? context.pop() : context.go('/login');
    });
  }

  Future<bool> _resendCode() async {
    try {
      await context.api.forgotPassword(_email.text.trim());
      if (mounted) context.snack(context.t('code_sent'));
      return true;
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
      return false;
    }
  }

  void _backToEmail() {
    setState(() {
      _codeSent = false;
      _code.clear();
      _password.clear();
      _confirm.clear();
    });
  }

  void _goLogin() => context.canPop() ? context.pop() : context.go('/login');

  Widget _stepDot(bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: active ? 22 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? PetsyColors.primary : PetsyColors.border,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = _email.text.trim();

    return _AuthPageShell(
      onBack: () {
        if (_codeSent) {
          _backToEmail();
        } else {
          _goLogin();
        }
      },
      panel: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AuthPanelHeader(
            title: context.t(_codeSent ? 'forgot_code_headline' : 'forgot_headline'),
            support: context.t(_codeSent ? 'forgot_code_support' : 'forgot_support'),
            leading: Column(
              children: [
                _AuthIconBadge(_codeSent ? Icons.password_rounded : Icons.lock_reset_rounded),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _stepDot(!_codeSent),
                    const SizedBox(width: 8),
                    _stepDot(_codeSent),
                  ],
                ),
              ],
            ),
          ),
          if (_codeSent) ...[
            _EmailChip(email: email),
            const SizedBox(height: 18),
          ],
          Form(
            key: _form,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
              child: _codeSent
                  ? Column(
                      key: const ValueKey('reset'),
                      children: [
                        _OtpField(controller: _code),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.next,
                          decoration: _authFieldDecoration(
                            label: context.t('new_password'),
                            icon: Icons.lock_outline_rounded,
                            suffix: _AuthEyeButton(
                              obscure: _obscure,
                              onTap: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) => _passwordValidator(context, v),
                        ),
                        _PasswordStrength(controller: _password),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirm,
                          obscureText: _obscureConfirm,
                          textInputAction: TextInputAction.done,
                          decoration: _authFieldDecoration(
                            label: context.t('confirm_password'),
                            icon: Icons.lock_person_outlined,
                            suffix: _AuthEyeButton(
                              obscure: _obscureConfirm,
                              onTap: () => setState(() => _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                          validator: (v) {
                            if (v != _password.text) return context.t('passwords_mismatch');
                            return _passwordValidator(context, v);
                          },
                          onFieldSubmitted: (_) => _reset(),
                        ),
                      ],
                    )
                  : TextFormField(
                      key: const ValueKey('email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      textInputAction: TextInputAction.done,
                      decoration: _authFieldDecoration(
                        label: context.t('email'),
                        icon: Icons.mail_outline_rounded,
                      ),
                      validator: (v) => _emailValidator(context, v),
                      onFieldSubmitted: (_) => _sendCode(),
                    ),
            ),
          ),
          const SizedBox(height: 18),
          SubmitButton(
            label: context.t(_codeSent ? 'reset_password' : 'send_code'),
            busy: _busy,
            onPressed: _codeSent ? _reset : _sendCode,
          ),
          if (_codeSent) ...[
            const SizedBox(height: 4),
            _ResendButton(
              enabled: !_busy,
              onResend: _resendCode,
            ),
            TextButton(
              onPressed: _busy ? null : _backToEmail,
              child: Text(context.t('change_email')),
            ),
          ],
        ],
      ),
      footer: _codeSent
          ? null
          : TextButton(
              onPressed: _goLogin,
              child: Text(context.t('login'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
    );
  }
}
