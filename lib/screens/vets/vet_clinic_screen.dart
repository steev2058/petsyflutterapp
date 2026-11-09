import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'vet_screens.dart';

enum _ClinicFilter { requests, upcoming, past, cancelled }

/// The vet's side of bookings: accept or decline requests, then mark visits done.
class VetClinicAppointmentsScreen extends StatefulWidget {
  const VetClinicAppointmentsScreen({super.key});

  @override
  State<VetClinicAppointmentsScreen> createState() => _VetClinicAppointmentsScreenState();
}

class _VetClinicAppointmentsScreenState extends State<VetClinicAppointmentsScreen> {
  _ClinicFilter _filter = _ClinicFilter.requests;
  final Set<String> _busyIds = {};

  static bool _isPast(Appointment a) {
    final date = DateTime.tryParse(a.date);
    final now = DateTime.now();
    return date != null && date.isBefore(DateTime(now.year, now.month, now.day));
  }

  bool _matches(Appointment a, _ClinicFilter filter) => switch (filter) {
        _ClinicFilter.requests => a.status == 'pending',
        _ClinicFilter.upcoming => a.status == 'confirmed' && !_isPast(a),
        _ClinicFilter.past => a.status == 'completed' || (a.status == 'confirmed' && _isPast(a)),
        _ClinicFilter.cancelled => a.status == 'cancelled',
      };

  Future<void> _act(Appointment a, String action, Future<void> Function() reload) async {
    if (action == 'decline') {
      final ok = await confirmAction(
        context,
        title: context.t('vet_decline_title'),
        message: context.t('vet_decline_confirm'),
        confirmLabel: context.t('vet_decline'),
        cancelLabel: context.t('appt_keep'),
      );
      if (!ok || !mounted) return;
    }
    final done = context.t(switch (action) {
      'accept' => 'vet_accepted',
      'decline' => 'vet_declined',
      _ => 'vet_completed',
    });
    setState(() => _busyIds.add(a.id));
    try {
      await context.api.updateVetAppointment(a.id, action);
      if (!mounted) return;
      context.snack(done);
      await reload();
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(a.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filters = <(_ClinicFilter, String, IconData)>[
      (_ClinicFilter.requests, 'vet_filter_requests', Icons.mark_email_unread_outlined),
      (_ClinicFilter.upcoming, 'appt_filter_upcoming', Icons.event_available_rounded),
      (_ClinicFilter.past, 'appt_filter_past', Icons.history_rounded),
      (_ClinicFilter.cancelled, 'appt_filter_cancelled', Icons.event_busy_rounded),
    ];

    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(title: Text(context.t('vet_clinic_title'))),
      body: AsyncView<List<Appointment>>(
        loader: () => context.api.vetAppointments(),
        builder: (context, items, reload) {
          final visible = items.where((a) => _matches(a, _filter)).toList()
            ..sort((a, b) {
              final cmp = '${a.date} ${a.time}'.compareTo('${b.date} ${b.time}');
              return _filter == _ClinicFilter.past || _filter == _ClinicFilter.cancelled ? -cmp : cmp;
            });
          final requestCount = items.where((a) => _matches(a, _ClinicFilter.requests)).length;

          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsetsDirectional.fromSTEB(0, PetsySpacing.xs, 0, PetsySpacing.listBottom),
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    PetsySpacing.page,
                    0,
                    PetsySpacing.page,
                    0,
                  ),
                  child: Text(
                    context.t('vet_clinic_subtitle'),
                    style: PetsyType.meta.copyWith(fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                ),
                const SizedBox(height: PetsySpacing.md),
                PetsyFilterRow(
                  children: [
                    for (final (value, label, icon) in filters)
                      PetsyPill(
                        label: context.t(label),
                        icon: icon,
                        selected: _filter == value,
                        count: value == _ClinicFilter.requests && requestCount > 0 ? requestCount : null,
                        highlightCount: true,
                        onTap: () => setState(() => _filter = value),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      PetsySpacing.page,
                      36,
                      PetsySpacing.page,
                      0,
                    ),
                    child: MessageView(
                      icon: Icons.calendar_month_outlined,
                      text: context.t('vet_clinic_empty'),
                    ),
                  )
                else
                  for (final a in visible)
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        PetsySpacing.page,
                        0,
                        PetsySpacing.page,
                        PetsySpacing.md,
                      ),
                      child: _ClinicAppointmentCard(
                        appointment: a,
                        busy: _busyIds.contains(a.id),
                        onAccept: a.status == 'pending' ? () => _act(a, 'accept', reload) : null,
                        onDecline: a.status == 'pending' || (a.status == 'confirmed' && !_isPast(a))
                            ? () => _act(a, 'decline', reload)
                            : null,
                        onComplete: a.status == 'confirmed' && !DateTime.now().isBefore(DateTime.tryParse(a.date) ?? DateTime(9999))
                            ? () => _act(a, 'complete', reload)
                            : null,
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ClinicAppointmentCard extends StatelessWidget {
  const _ClinicAppointmentCard({
    required this.appointment,
    required this.busy,
    this.onAccept,
    this.onDecline,
    this.onComplete,
  });

  final Appointment appointment;
  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final locale = Localizations.localeOf(context).languageCode;
    final date = DateTime.tryParse(a.date);
    final cancelled = a.status == 'cancelled';
    final petLine = [
      if (a.petName != null && a.petName!.isNotEmpty) a.petName!,
      if (a.petSpecies != null && a.petSpecies!.isNotEmpty) context.t(a.petSpecies!),
    ].join(' · ');
    final hasActions = onAccept != null || onDecline != null || onComplete != null;

    return Container(
      padding: const EdgeInsets.all(PetsySpacing.md + 2),
      decoration: BoxDecoration(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.xl),
        border: Border.all(color: PetsyColors.border),
        boxShadow: PetsyShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: cancelled ? PetsyColors.backgroundAlt : PetsyColors.accentSoft,
                  borderRadius: BorderRadius.circular(PetsyRadius.lg),
                ),
                child: Column(
                  children: [
                    Text(
                      date == null ? '—' : '${date.day}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        color: cancelled ? PetsyColors.textLight : PetsyColors.accent,
                      ),
                    ),
                    Text(
                      date == null ? a.date : DateFormat.MMM(locale).format(date),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: cancelled ? PetsyColors.textLight : PetsyColors.accent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      a.time,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: PetsyColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            a.ownerName ?? context.t('vet_owner'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                          ),
                        ),
                        StatusChip(a.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appointmentReasonLabel(context, a.reason),
                      style: const TextStyle(color: PetsyColors.textSecondary, fontWeight: FontWeight.w600),
                    ),
                    if (petLine.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.pets_rounded, size: 15, color: PetsyColors.primaryDark),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(petLine, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                          ),
                        ],
                      ),
                    ],
                    if (a.notes != null && a.notes!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        a.notes!,
                        style: const TextStyle(fontSize: 12.5, color: PetsyColors.textSecondary, height: 1.4),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${context.t('appointment_fee')}: ${formatPrice(a.fee)} · ${appointmentPaymentLabel(context, a)}',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: appointmentPaymentColor(a)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasActions) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: PetsyColors.border),
            const SizedBox(height: 10),
            if (busy)
              const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)))
            else
              Row(
                children: [
                  if (onAccept != null)
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                        onPressed: onAccept,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(context.t('vet_accept')),
                      ),
                    ),
                  if (onComplete != null)
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          backgroundColor: PetsyColors.success,
                        ),
                        onPressed: onComplete,
                        icon: const Icon(Icons.task_alt_rounded, size: 18),
                        label: Text(context.t('vet_complete')),
                      ),
                    ),
                  if (onDecline != null) ...[
                    if (onAccept != null || onComplete != null) const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          foregroundColor: PetsyColors.error,
                          side: BorderSide(color: PetsyColors.error.withValues(alpha: 0.5)),
                        ),
                        onPressed: onDecline,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: Text(context.t('vet_decline')),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ],
      ),
    );
  }
}
