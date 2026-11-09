import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../auth/auth_screens.dart';

const _healthTypes = ['vaccination', 'checkup', 'treatment', 'weight', 'other'];

final _weightRe = RegExp(r'(\d+(?:[.,]\d+)?)');

String _healthTypeKey(String type) => switch (type) {
      'vaccination' => 'health_vaccination',
      'checkup' => 'health_checkup',
      'treatment' => 'health_treatment',
      'weight' => 'health_weight',
      _ => 'health_other',
    };

IconData _healthTypeIcon(String type) => switch (type) {
      'vaccination' => Icons.vaccines_outlined,
      'checkup' => Icons.medical_services_outlined,
      'treatment' => Icons.healing_outlined,
      'weight' => Icons.monitor_weight_outlined,
      _ => Icons.note_alt_outlined,
    };

(Color, Color) _healthTypeColors(String type) => switch (type) {
      'vaccination' => (PetsyColors.accent, PetsyColors.accentSoft),
      'checkup' => (PetsyColors.primaryDark, PetsyColors.primarySoft),
      'treatment' => (PetsyColors.secondary, PetsyColors.mist),
      'weight' => (PetsyColors.ratingInk, PetsyColors.ratingSoft),
      _ => (PetsyColors.textSecondary, PetsyColors.shellWash),
    };

String _kgText(double kg) => kg.toStringAsFixed(kg.truncateToDouble() == kg ? 0 : 1);

double? parseWeightKg(HealthRecord r) {
  for (final raw in [r.title, r.description, r.notes]) {
    if (raw == null || raw.trim().isEmpty) continue;
    final m = _weightRe.firstMatch(raw.replaceAll(',', '.'));
    if (m == null) continue;
    final v = double.tryParse(m.group(1)!);
    if (v != null && v > 0 && v < 500) return v;
  }
  return null;
}

class _WeightPoint {
  const _WeightPoint({required this.date, required this.kg});
  final DateTime date;
  final double kg;
}

List<_WeightPoint> _weightPointsFrom(List<HealthRecord> items) {
  final points = <_WeightPoint>[];
  for (final r in items.where((e) => e.recordType == 'weight')) {
    final kg = parseWeightKg(r);
    final date = DateTime.tryParse(r.date);
    if (kg == null || date == null) continue;
    points.add(_WeightPoint(date: date, kg: kg));
  }
  points.sort((a, b) => a.date.compareTo(b.date));
  return points;
}

class PetHealthScreen extends StatefulWidget {
  const PetHealthScreen({super.key, required this.petId, this.petName});

  final String petId;
  final String? petName;

  @override
  State<PetHealthScreen> createState() => _PetHealthScreenState();
}

class _PetHealthScreenState extends State<PetHealthScreen> {
  final _view = GlobalKey<AsyncViewState<List<HealthRecord>>>();
  String? _filter;

  Future<void> _add() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PetsyColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(PetsyRadius.xl)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: _AddHealthRecordSheet(petId: widget.petId, initialType: _filter),
      ),
    );
    if (added == true) _view.currentState?.reload();
  }

  Future<void> _delete(HealthRecord record) async {
    final ok = await confirmAction(
      context,
      title: context.t('health_delete'),
      message: context.t('health_delete_confirm'),
      confirmLabel: context.t('health_delete'),
    );
    if (!ok || !mounted) return;
    try {
      await context.api.deleteHealthRecord(record.id);
      if (!mounted) return;
      context.snack(context.t('health_deleted'));
      _view.currentState?.reload();
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(
        title: Text(
          widget.petName == null || widget.petName!.isEmpty
              ? context.t('health_records')
              : '${context.t('health_records')} · ${widget.petName}',
        ),
      ),
      floatingActionButton: PetsyFab(
        heroTag: 'health-fab',
        icon: Icons.medical_services_rounded,
        label: context.t('add_health_record'),
        onPressed: _add,
      ),
      body: AsyncView<List<HealthRecord>>(
        key: _view,
        loader: () => context.api.healthRecords(widget.petId),
        builder: (context, items, reload) {
          final sorted = [...items]..sort((a, b) => b.date.compareTo(a.date));
          final weights = _weightPointsFrom(items);
          final visible = _filter == null ? sorted : sorted.where((r) => r.recordType == _filter).toList();
          final lastVaccine = sorted.where((r) => r.recordType == 'vaccination').firstOrNull;
          final lastCheckup = sorted.where((r) => r.recordType == 'checkup').firstOrNull;

          final children = <Widget>[
            Text(
              context.t('health_subtitle'),
              style: PetsyType.meta.copyWith(fontWeight: FontWeight.w600, fontSize: 13.5),
            ),
            const SizedBox(height: PetsySpacing.md),
            _HealthSummaryCard(
              total: items.length,
              lastVaccine: lastVaccine == null ? null : _formatRecordDate(context, lastVaccine.date),
              lastCheckup: lastCheckup == null ? null : _formatRecordDate(context, lastCheckup.date),
              latestKg: weights.isEmpty ? null : weights.last.kg,
            ),
            const SizedBox(height: PetsySpacing.md),
            _WeightChartCard(points: weights),
            const SizedBox(height: PetsySpacing.md + 2),
            PetsyFilterRow(
              padding: EdgeInsets.zero,
              children: [
                for (var i = 0; i < _healthTypes.length + 1; i++)
                  PetsyPill(
                    label: context.t(i == 0 ? 'health_all' : _healthTypeKey(_healthTypes[i - 1])),
                    icon: i == 0 ? Icons.grid_view_rounded : _healthTypeIcon(_healthTypes[i - 1]),
                    selected: (i == 0 ? null : _healthTypes[i - 1]) == _filter,
                    onTap: () => setState(() => _filter = i == 0 ? null : _healthTypes[i - 1]),
                  ),
              ],
            ),
            const SizedBox(height: PetsySpacing.md),
          ];

          if (items.isEmpty) {
            children.add(
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: MessageView(
                  icon: Icons.health_and_safety_outlined,
                  text: '${context.t('health_empty')}\n${context.t('health_empty_body')}',
                ),
              ),
            );
          } else if (visible.isEmpty) {
            children.add(
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: MessageView(
                  icon: _healthTypeIcon(_filter ?? 'other'),
                  text: context.t('health_empty_filter'),
                  action: TextButton(
                    onPressed: () => setState(() => _filter = null),
                    child: Text(context.t('health_all')),
                  ),
                ),
              ),
            );
          } else {
            String? lastMonth;
            for (var i = 0; i < visible.length; i++) {
              final r = visible[i];
              final date = DateTime.tryParse(r.date);
              final month = date == null ? r.date : DateFormat.yMMMM(locale).format(date);
              if (month != lastMonth) {
                lastMonth = month;
                children.add(
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 8, bottom: 8),
                    child: Text(month, style: PetsyType.meta.copyWith(fontWeight: FontWeight.w800)),
                  ),
                );
              }
              final isLastInGroup = i == visible.length - 1 ||
                  (() {
                    final next = DateTime.tryParse(visible[i + 1].date);
                    final nextMonth = next == null ? visible[i + 1].date : DateFormat.yMMMM(locale).format(next);
                    return nextMonth != month;
                  })();
              children.add(
                _HealthTimelineTile(
                  record: r,
                  dateLabel: _formatRecordDate(context, r.date),
                  showLine: !isLastInGroup,
                  onDelete: () => _delete(r),
                ),
              );
            }
          }

          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsetsDirectional.fromSTEB(
                PetsySpacing.page,
                PetsySpacing.md,
                PetsySpacing.page,
                96,
              ),
              children: children,
            ),
          );
        },
      ),
    );
  }
}

String _formatRecordDate(BuildContext context, String raw) {
  final d = DateTime.tryParse(raw);
  return d == null ? raw : context.formatDate(d);
}

class _HealthSummaryCard extends StatelessWidget {
  const _HealthSummaryCard({
    required this.total,
    required this.lastVaccine,
    required this.lastCheckup,
    required this.latestKg,
  });

  final int total;
  final String? lastVaccine;
  final String? lastCheckup;
  final double? latestKg;

  @override
  Widget build(BuildContext context) {
    final countLabel =
        total == 1 ? context.t('health_count_one') : context.t('health_count').replaceAll('{count}', '$total');
    return Container(
      padding: const EdgeInsets.all(PetsySpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PetsyRadius.xl),
        color: PetsyColors.surface,
        border: Border.all(color: PetsyColors.border),
        boxShadow: PetsyShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: PetsyColors.accentSoft,
                  borderRadius: BorderRadius.circular(PetsyRadius.md),
                ),
                child: const Icon(Icons.health_and_safety_rounded, color: PetsyColors.accent),
              ),
              const SizedBox(width: PetsySpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.t('health_records'), style: PetsyType.section),
                    Text(countLabel, style: PetsyType.meta),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: PetsySpacing.md + 2),
          Row(
            children: [
              _SummaryStat(
                icon: Icons.vaccines_outlined,
                label: context.t('health_last_vaccine'),
                value: lastVaccine ?? context.t('health_none_yet'),
              ),
              const SizedBox(width: 8),
              _SummaryStat(
                icon: Icons.medical_services_outlined,
                label: context.t('health_last_visit'),
                value: lastCheckup ?? context.t('health_none_yet'),
              ),
              const SizedBox(width: 8),
              _SummaryStat(
                icon: Icons.monitor_weight_outlined,
                label: context.t('weight_latest'),
                value: latestKg == null ? context.t('health_none_yet') : '${_kgText(latestKg!)} ${context.t('kg')}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: PetsyColors.shellWash,
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          border: Border.all(color: PetsyColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: PetsyColors.accent, size: 18),
            const SizedBox(height: PetsySpacing.sm - 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PetsyType.meta.copyWith(fontSize: 11),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PetsyType.meta.copyWith(fontWeight: FontWeight.w800, fontSize: 12.5, color: PetsyColors.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthTimelineTile extends StatelessWidget {
  const _HealthTimelineTile({
    required this.record,
    required this.dateLabel,
    required this.showLine,
    required this.onDelete,
  });

  final HealthRecord record;
  final String dateLabel;
  final bool showLine;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final (fg, bg) = _healthTypeColors(r.recordType);
    final details = r.description ?? r.notes;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: bg,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Icon(_healthTypeIcon(r.recordType), color: fg, size: 20),
                ),
                if (showLine)
                  Expanded(
                    child: Container(width: 2, color: PetsyColors.border),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
                decoration: BoxDecoration(
                  color: PetsyColors.surface,
                  borderRadius: BorderRadius.circular(PetsyRadius.lg),
                  border: Border.all(color: PetsyColors.border),
                  boxShadow: PetsyShadows.soft,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
                                child: Text(
                                  context.t(_healthTypeKey(r.recordType)),
                                  style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w800),
                                ),
                              ),
                              if (r.appointmentId != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: PetsyColors.primarySoft,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.event_available_rounded, size: 12, color: PetsyColors.primaryDark),
                                      const SizedBox(width: 3),
                                      Text(
                                        context.t('health_from_appointment'),
                                        style: const TextStyle(
                                          color: PetsyColors.primaryDark,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(r.title, style: PetsyType.cardTitle),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.event_rounded, size: 14, color: PetsyColors.textLight),
                              const SizedBox(width: 4),
                              Text(
                                dateLabel,
                                style: const TextStyle(
                                  color: PetsyColors.textSecondary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (r.vetName != null && r.vetName!.isNotEmpty) ...[
                                const SizedBox(width: 10),
                                const Icon(Icons.person_outline_rounded, size: 14, color: PetsyColors.textLight),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    r.vetName!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: PetsyColors.textSecondary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (details != null && details.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              details,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(height: 1.4, fontSize: 13),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: context.t('health_delete'),
                      visualDensity: VisualDensity.compact,
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded, color: PetsyColors.textLight, size: 20),
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

class _WeightChartCard extends StatelessWidget {
  const _WeightChartCard({required this.points});

  final List<_WeightPoint> points;

  @override
  Widget build(BuildContext context) {
    final latest = points.isEmpty ? null : points.last;
    final delta = points.length < 2 ? null : points.last.kg - points[points.length - 2].kg;
    final deltaColor = delta == null || delta == 0 ? PetsyColors.textSecondary : PetsyColors.primaryDark;
    final deltaIcon = delta == null || delta == 0
        ? Icons.trending_flat_rounded
        : (delta > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded);

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        PetsySpacing.md + 2,
        PetsySpacing.md + 2,
        PetsySpacing.md + 2,
        PetsySpacing.md,
      ),
      decoration: BoxDecoration(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.xl),
        border: Border.all(color: PetsyColors.border),
        boxShadow: PetsyShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: PetsyColors.ratingSoft,
                  borderRadius: BorderRadius.circular(PetsyRadius.sm),
                ),
                child: const Icon(Icons.show_chart_rounded, color: PetsyColors.ratingInk, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(context.t('weight_chart'), style: PetsyType.cardTitle),
              ),
              if (latest != null)
                Text(
                  '${_kgText(latest.kg)} ${context.t('kg')}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
            ],
          ),
          if (delta != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(deltaIcon, size: 16, color: deltaColor),
                const SizedBox(width: 4),
                Text(
                  '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)} ${context.t('kg')} ${context.t('health_since_last')}',
                  style: TextStyle(color: deltaColor, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          if (points.length < 2)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              decoration: BoxDecoration(
                color: PetsyColors.backgroundAlt,
                borderRadius: BorderRadius.circular(PetsyRadius.md),
              ),
              child: Row(
                children: [
                  const Icon(Icons.monitor_weight_outlined, color: PetsyColors.textLight),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.t('weight_points_needed'),
                      style: const TextStyle(color: PetsyColors.textSecondary, height: 1.35),
                    ),
                  ),
                ],
              ),
            )
          else
            Directionality(
              textDirection: TextDirection.ltr,
              child: SizedBox(
                height: 160,
                width: double.infinity,
                child: CustomPaint(painter: _WeightChartPainter(points)),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeightChartPainter extends CustomPainter {
  _WeightChartPainter(this.points);

  final List<_WeightPoint> points;

  static const _line = PetsyColors.ratingInk;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final minKg = points.map((e) => e.kg).reduce(math.min);
    final maxKg = points.map((e) => e.kg).reduce(math.max);
    final span = math.max(maxKg - minKg, 0.5);
    const padL = 32.0;
    const padR = 10.0;
    const padT = 12.0;
    const padB = 22.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;

    final grid = Paint()
      ..color = PetsyColors.border
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = padT + h * i / 3;
      canvas.drawLine(Offset(padL, y), Offset(size.width - padR, y), grid);
    }

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    void label(String text, Offset at, {TextAlign align = TextAlign.left}) {
      textPainter.text = TextSpan(
        text: text,
        style: const TextStyle(color: PetsyColors.textLight, fontSize: 10, fontWeight: FontWeight.w600),
      );
      textPainter.layout();
      final dx = align == TextAlign.right ? at.dx - textPainter.width : at.dx;
      textPainter.paint(canvas, Offset(dx, at.dy));
    }

    for (var i = 0; i < 4; i++) {
      final kg = minKg + span * (1 - i / 3);
      label(kg.toStringAsFixed(1), Offset(0, padT + h * i / 3 - 6));
    }

    Offset pointAt(int i) {
      final t = i / (points.length - 1);
      final x = padL + w * t;
      final y = padT + h * (1 - ((points[i].kg - minKg) / span));
      return Offset(x, y);
    }

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < points.length; i++) {
      final prev = pointAt(i - 1);
      final cur = pointAt(i);
      final midX = (prev.dx + cur.dx) / 2;
      path.cubicTo(midX, prev.dy, midX, cur.dy, cur.dx, cur.dy);
    }
    final fill = Path.from(path)
      ..lineTo(pointAt(points.length - 1).dx, padT + h)
      ..lineTo(pointAt(0).dx, padT + h)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_line.withValues(alpha: 0.22), _line.withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTWH(0, padT, size.width, h)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (var i = 0; i < points.length; i++) {
      final p = pointAt(i);
      final isLast = i == points.length - 1;
      canvas.drawCircle(p, isLast ? 6 : 4, Paint()..color = Colors.white);
      canvas.drawCircle(p, isLast ? 4.4 : 2.8, Paint()..color = _line);
    }

    label(
      '${points.first.date.day}/${points.first.date.month}',
      Offset(padL, size.height - 14),
    );
    label(
      '${points.last.date.day}/${points.last.date.month}',
      Offset(size.width - padR, size.height - 14),
      align: TextAlign.right,
    );
  }

  @override
  bool shouldRepaint(covariant _WeightChartPainter oldDelegate) => oldDelegate.points != points;
}

class _AddHealthRecordSheet extends StatefulWidget {
  const _AddHealthRecordSheet({
    required this.petId,
    this.initialType,
    this.initialTitle,
    this.initialDate,
    this.initialVetName,
    this.appointmentId,
  });

  final String petId;
  final String? initialType;
  final String? initialTitle;
  final String? initialDate;
  final String? initialVetName;
  final String? appointmentId;

  @override
  State<_AddHealthRecordSheet> createState() => _AddHealthRecordSheetState();
}

class _AddHealthRecordSheetState extends State<_AddHealthRecordSheet> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initialTitle ?? '');
  late final _vet = TextEditingController(text: widget.initialVetName ?? '');
  late final _notes = TextEditingController();
  late final _weight = TextEditingController();
  late String _type = widget.initialType ?? 'checkup';
  late DateTime _date = () {
    final raw = widget.initialDate;
    if (raw != null && raw.isNotEmpty) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _vet.dispose();
    _notes.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final isWeight = _type == 'weight';
      final kg = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
      final title = isWeight && kg != null
          ? '${kg.toStringAsFixed(kg.truncateToDouble() == kg ? 0 : 1)} كغ'
          : _title.text.trim();
      await context.api.createHealthRecord({
        'pet_id': widget.petId,
        'record_type': _type,
        'title': title,
        'date': _date.toIso8601String().split('T').first,
        'vet_name': _vet.text.trim().isEmpty ? null : _vet.text.trim(),
        'description': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'appointment_id': widget.appointmentId,
      });
      if (!mounted) return;
      context.snack(context.t('health_saved'));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWeight = _type == 'weight';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: PetsyColors.border, borderRadius: BorderRadius.circular(99)),
                ),
              ),
              const SizedBox(height: 16),
              Text(context.t('add_health_record'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Text(
                context.t('health_type'),
                style: const TextStyle(fontWeight: FontWeight.w700, color: PetsyColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _healthTypes) _TypeOption(type: t, selected: _type == t, onTap: () => setState(() => _type = t)),
                ],
              ),
              const SizedBox(height: 16),
              if (isWeight)
                TextFormField(
                  controller: _weight,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: InputDecoration(
                    labelText: context.t('weight_kg'),
                    suffixText: context.t('kg'),
                    prefixIcon: const Icon(Icons.monitor_weight_outlined),
                  ),
                  validator: (v) {
                    final n = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                    if (n == null || n <= 0) return context.t('required');
                    return null;
                  },
                )
              else
                TextFormField(
                  controller: _title,
                  decoration: InputDecoration(
                    labelText: context.t('health_title'),
                    hintText: context.t('health_title_hint'),
                    prefixIcon: Icon(_healthTypeIcon(_type)),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? context.t('required') : null,
                ),
              const SizedBox(height: 12),
              Material(
                color: PetsyColors.backgroundAlt,
                borderRadius: BorderRadius.circular(PetsyRadius.md),
                child: InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(PetsyRadius.md),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.event_rounded, color: PetsyColors.primaryDark),
                        const SizedBox(width: 10),
                        Text(
                          context.t('health_date'),
                          style: const TextStyle(color: PetsyColors.textSecondary, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text(context.formatDate(_date), style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(width: 6),
                        const Icon(Icons.expand_more_rounded, color: PetsyColors.textLight),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _vet,
                decoration: InputDecoration(
                  labelText: context.t('health_vet'),
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                decoration: InputDecoration(labelText: context.t('health_notes'), alignLabelWithHint: true),
              ),
              const SizedBox(height: 18),
              SubmitButton(label: context.t('save'), busy: _busy, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeOption extends StatelessWidget {
  const _TypeOption({required this.type, required this.selected, required this.onTap});

  final String type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _healthTypeColors(type);
    return Material(
      color: selected ? bg : PetsyColors.surface,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? fg : PetsyColors.border, width: selected ? 1.5 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_healthTypeIcon(type), size: 17, color: selected ? fg : PetsyColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                context.t(_healthTypeKey(type)),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: selected ? fg : PetsyColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool?> showAddHealthFromAppointment(
  BuildContext context, {
  required String petId,
  required String title,
  required String date,
  String? vetName,
  String? appointmentId,
  String recordType = 'checkup',
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PetsyColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(PetsyRadius.xl)),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _AddHealthRecordSheet(
        petId: petId,
        initialType: recordType,
        initialTitle: title,
        initialDate: date,
        initialVetName: vetName,
        appointmentId: appointmentId,
      ),
    ),
  );
}
