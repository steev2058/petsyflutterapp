import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'training_screens.dart';

/// Admin queue to approve or reject trainer applications.
class AdminTrainerApplicationsScreen extends StatefulWidget {
  const AdminTrainerApplicationsScreen({super.key});

  @override
  State<AdminTrainerApplicationsScreen> createState() => _AdminTrainerApplicationsScreenState();
}

class _AdminTrainerApplicationsScreenState extends State<AdminTrainerApplicationsScreen> {
  String _status = 'pending_verification';
  int _reload = 0;

  Future<void> _review(Trainer trainer, {required bool approve}) async {
    String? notes;
    if (!approve) {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.t('trainer_review_reject_title')),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(hintText: context.t('trainer_review_reject_hint')),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.t('trainer_review_reject'))),
          ],
        ),
      );
      notes = controller.text.trim();
      controller.dispose();
      if (ok != true || !mounted) return;
      if (notes.isEmpty) {
        context.snack(context.t('trainer_review_reject_required'), error: true);
        return;
      }
    } else {
      final ok = await confirmAction(
        context,
        title: context.t('trainer_review_approve_title'),
        message: context.t('trainer_review_approve_body').replaceAll('{name}', trainer.name),
        confirmLabel: context.t('trainer_review_approve'),
        color: PetsyColors.success,
        icon: Icons.verified_rounded,
      );
      if (!ok || !mounted) return;
    }

    try {
      await context.api.reviewTrainer(
        trainer.id,
        action: approve ? 'approve' : 'reject',
        notes: notes,
      );
      if (!mounted) return;
      context.snack(
        context.t(approve ? 'trainer_review_approved' : 'trainer_review_rejected'),
        success: true,
        icon: approve ? Icons.verified_rounded : Icons.cancel_outlined,
      );
      setState(() => _reload++);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PetsyPage(
      appBar: AppBar(title: Text(context.t('trainer_review_title'))),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
            child: PetsyFilterRow(
              children: [
                for (final s in const ['pending_verification', 'active', 'rejected'])
                  PetsyPill(
                    label: context.t('trainer_status_$s'),
                    selected: _status == s,
                    onTap: () => setState(() => _status = s),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView<List<Trainer>>(
              key: ValueKey('$_status-$_reload'),
              loader: () => context.api.adminTrainers(status: _status),
              isEmpty: (items) => items.isEmpty,
              emptyIcon: Icons.school_outlined,
              emptyText: context.t('trainer_review_empty'),
              builder: (context, items, reload) {
                return RefreshIndicator(
                  onRefresh: reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 8, PetsySpacing.page, PetsySpacing.listBottom),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final t = items[i];
                      return _TrainerApplicationCard(
                        trainer: t,
                        onApprove: t.isPending ? () => _review(t, approve: true) : null,
                        onReject: t.isPending ? () => _review(t, approve: false) : null,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TrainerApplicationCard extends StatelessWidget {
  const _TrainerApplicationCard({
    required this.trainer,
    this.onApprove,
    this.onReject,
  });

  final Trainer trainer;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PetsyColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        side: const BorderSide(color: PetsyColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: NetImage(trainer.image, icon: Icons.school_outlined),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(trainer.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      if ((trainer.title ?? '').isNotEmpty)
                        Text(trainer.title!, style: const TextStyle(color: PetsyColors.accent, fontWeight: FontWeight.w700, fontSize: 12.5)),
                      Text(
                        [
                          if ((trainer.city ?? '').isNotEmpty) trainer.city!,
                          if ((trainer.country ?? '').isNotEmpty) context.t('country_${trainer.country}'),
                          '${trainer.experienceYears} ${context.t('years_experience')}',
                        ].join(' · '),
                        style: const TextStyle(color: PetsyColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                StatusChip(trainer.status),
              ],
            ),
            if (trainer.categories.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in trainer.categories)
                    PetsyMetaBadge(
                      label: context.t('trainer_cat_$c'),
                      icon: trainerCategoryIcon(c),
                      tone: PetsyMetaTone.primary,
                    ),
                ],
              ),
            ],
            if ((trainer.bio ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                trainer.bio!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.35, fontWeight: FontWeight.w600),
              ),
            ],
            if ((trainer.verificationNotes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                trainer.verificationNotes!,
                style: const TextStyle(color: PetsyColors.error, fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
            ],
            if (onApprove != null || onReject != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.close_rounded),
                      label: Text(context.t('trainer_review_reject')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onApprove,
                      icon: const Icon(Icons.check_rounded),
                      label: Text(context.t('trainer_review_approve')),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
