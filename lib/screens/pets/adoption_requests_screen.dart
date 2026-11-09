import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

const _adoptionMessageMin = 20;

/// Opens (or continues) a chat with [otherUserId] about the pet.
Future<void> openAdoptionChat(
  BuildContext context, {
  required String otherUserId,
  required String petId,
  required String petName,
}) async {
  try {
    final conversationId = await context.api.startConversation(
      otherUserId: otherUserId,
      petId: petId,
      message: context.t('adoption_chat_opening').replaceAll('{pet}', petName),
    );
    if (context.mounted) context.push('/chat/$conversationId');
  } catch (e) {
    if (context.mounted) context.snack(context.errorText(e), error: true);
  }
}

/// Asks the user to introduce themselves and sends the request. Returns true when sent.
Future<bool> showAdoptionRequestSheet(BuildContext context, Pet pet) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PetsyColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(PetsyRadius.xl))),
    builder: (_) => _AdoptionRequestSheet(pet: pet),
  );
  return sent == true;
}

class _AdoptionRequestSheet extends StatefulWidget {
  const _AdoptionRequestSheet({required this.pet});

  final Pet pet;

  @override
  State<_AdoptionRequestSheet> createState() => _AdoptionRequestSheetState();
}

class _AdoptionRequestSheetState extends State<_AdoptionRequestSheet> {
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _message.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await context.api.requestAdoption(widget.pet.id, _message.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        context.snack(context.errorText(e), error: true);
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final length = _message.text.trim().length;
    final ready = length >= _adoptionMessageMin;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: PetsyColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.t('adoption_sheet_title').replaceAll('{pet}', widget.pet.name),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              context.t('adoption_sheet_hint'),
              style: const TextStyle(color: PetsyColors.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _message,
              autofocus: true,
              minLines: 4,
              maxLines: 7,
              maxLength: 600,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.t('adoption_sheet_field'),
                alignLabelWithHint: true,
                helperText: ready ? null : context.t('adoption_sheet_min').replaceAll('{count}', '$_adoptionMessageMin'),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: ready && !_sending ? _send : null,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.favorite_rounded),
              label: Text(context.t('adoption_sheet_send')),
            ),
          ],
        ),
      ),
    );
  }
}

enum _AdoptionTab { incoming, sent }

/// Adoption requests for the user's pets, and the requests they sent.
class AdoptionRequestsScreen extends StatefulWidget {
  const AdoptionRequestsScreen({super.key, this.initialTab});

  final String? initialTab;

  @override
  State<AdoptionRequestsScreen> createState() => _AdoptionRequestsScreenState();
}

class _AdoptionRequestsScreenState extends State<AdoptionRequestsScreen> {
  late _AdoptionTab _tab = widget.initialTab == 'sent' ? _AdoptionTab.sent : _AdoptionTab.incoming;
  final Set<String> _busyIds = {};

  Future<(List<AdoptionRequest>, List<AdoptionRequest>)> _load() async {
    final api = context.api;
    final results = await Future.wait([api.adoptionRequests('incoming'), api.adoptionRequests('sent')]);
    return (results[0], results[1]);
  }

  Future<void> _act(AdoptionRequest r, String action, Future<void> Function() reload) async {
    final pet = r.petName ?? '';
    final name = r.requesterName ?? context.t('someone');
    final ok = await switch (action) {
      'accept' => confirmAction(
          context,
          title: context.t('adoption_accept_title').replaceAll('{name}', name),
          message: context.t('adoption_accept_message').replaceAll('{pet}', pet),
          confirmLabel: context.t('adoption_accept'),
          color: PetsyColors.success,
          icon: Icons.favorite_rounded,
        ),
      'decline' => confirmAction(
          context,
          title: context.t('adoption_decline_title'),
          message: context.t('adoption_decline_message'),
          confirmLabel: context.t('adoption_decline'),
          icon: Icons.heart_broken_outlined,
        ),
      _ => confirmAction(
          context,
          title: context.t('adoption_withdraw_title'),
          message: context.t('adoption_withdraw_message'),
          confirmLabel: context.t('adoption_withdraw'),
          icon: Icons.undo_rounded,
        ),
    };
    if (!ok || !mounted) return;
    final done = context.t(switch (action) {
      'accept' => 'adoption_accepted_snack',
      'decline' => 'adoption_declined_snack',
      _ => 'adoption_withdrawn_snack',
    });
    setState(() => _busyIds.add(r.id));
    try {
      await context.api.updateAdoptionRequest(r.id, action);
      if (!mounted) return;
      context.snack(
        done,
        success: action == 'accept',
        icon: switch (action) {
          'accept' => Icons.favorite_rounded,
          'decline' => Icons.close_rounded,
          _ => Icons.undo_rounded,
        },
      );
      await reload();
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(r.id));
    }
  }

  static int _rank(AdoptionRequest r) => switch (r.status) {
        'pending' => 0,
        'accepted' => 1,
        _ => 2,
      };

  static List<AdoptionRequest> _sorted(List<AdoptionRequest> items) => [...items]
    ..sort((a, b) {
      final byStatus = _rank(a).compareTo(_rank(b));
      if (byStatus != 0) return byStatus;
      return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
    });

  @override
  Widget build(BuildContext context) {
    return PetsyPage(
      appBar: AppBar(title: Text(context.t('adoption_requests_title'))),
      child: AsyncView<(List<AdoptionRequest>, List<AdoptionRequest>)>(
        loader: _load,
        builder: (context, data, reload) {
          final (incoming, sent) = data;
          final incomingPending = incoming.where((r) => r.isPending).length;
          final visible = _sorted(_tab == _AdoptionTab.incoming ? incoming : sent);

          return RefreshIndicator(
            onRefresh: reload,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: _AdoptionHero()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 14, PetsySpacing.page, 0),
                    child: _AdoptionStatsRow(
                      pending: incomingPending,
                      incoming: incoming.length,
                      sent: sent.length,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 14, PetsySpacing.page, 8),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: PetsyColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: PetsyColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _AdoptionTabChip(
                              label: context.t('adoption_tab_incoming'),
                              icon: Icons.inbox_rounded,
                              count: incomingPending > 0 ? incomingPending : incoming.length,
                              highlight: incomingPending > 0,
                              selected: _tab == _AdoptionTab.incoming,
                              onTap: () => setState(() => _tab = _AdoptionTab.incoming),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _AdoptionTabChip(
                              label: context.t('adoption_tab_sent'),
                              icon: Icons.send_rounded,
                              count: sent.length,
                              highlight: false,
                              selected: _tab == _AdoptionTab.sent,
                              onTap: () => setState(() => _tab = _AdoptionTab.sent),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        PetsySpacing.page,
                        8,
                        PetsySpacing.page,
                        PetsySpacing.listBottom,
                      ),
                      child: _AdoptionEmptyState(incoming: _tab == _AdoptionTab.incoming),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      PetsySpacing.page,
                      4,
                      PetsySpacing.page,
                      PetsySpacing.listBottom,
                    ),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final r = visible[i];
                        return _AdoptionRequestCard(
                          request: r,
                          incoming: _tab == _AdoptionTab.incoming,
                          busy: _busyIds.contains(r.id),
                          onAction: (action) => _act(r, action, reload),
                        );
                      },
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

class _AdoptionHero extends StatefulWidget {
  const _AdoptionHero();

  @override
  State<_AdoptionHero> createState() => _AdoptionHeroState();
}

class _AdoptionHeroState extends State<_AdoptionHero> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(PetsySpacing.page, PetsySpacing.md, PetsySpacing.page, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PetsyRadius.xl),
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final t = Curves.easeInOut.transform(_pulse.value);
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1 + t * 0.2, -1),
                  end: Alignment(1, 1 - t * 0.15),
                  colors: const [
                    Color(0xFFC23A55),
                    PetsyColors.primary,
                    PetsyColors.secondary,
                  ],
                ),
              ),
              child: child,
            );
          },
          child: Stack(
            children: [
              Positioned(
                right: -18,
                top: -10,
                child: Icon(Icons.volunteer_activism_rounded, size: 112, color: Colors.white.withValues(alpha: 0.12)),
              ),
              Positioned(
                left: -16,
                bottom: -22,
                child: Icon(Icons.pets_rounded, size: 86, color: Colors.white.withValues(alpha: 0.08)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
                      ),
                      child: Text(
                        context.t('adoption_requests_hero_tag'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.t('adoption_requests_hero_title'),
                      style: PetsyType.title.copyWith(color: Colors.white, fontSize: 22, height: 1.2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t('adoption_requests_subtitle'),
                      style: PetsyType.meta.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.4,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdoptionStatsRow extends StatelessWidget {
  const _AdoptionStatsRow({
    required this.pending,
    required this.incoming,
    required this.sent,
  });

  final int pending;
  final int incoming;
  final int sent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _AdoptionStatTile(
            icon: Icons.mark_email_unread_outlined,
            label: context.t('adoption_stat_pending').replaceAll('{count}', '$pending'),
            color: PetsyColors.warning,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _AdoptionStatTile(
            icon: Icons.inbox_rounded,
            label: context.t('adoption_stat_incoming').replaceAll('{count}', '$incoming'),
            color: PetsyColors.primaryDark,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _AdoptionStatTile(
            icon: Icons.send_rounded,
            label: context.t('adoption_stat_sent').replaceAll('{count}', '$sent'),
            color: PetsyColors.accent,
          ),
        ),
      ],
    );
  }
}

class _AdoptionStatTile extends StatelessWidget {
  const _AdoptionStatTile({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        border: Border.all(color: PetsyColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: color),
          ),
        ],
      ),
    );
  }
}

class _AdoptionTabChip extends StatelessWidget {
  const _AdoptionTabChip({
    required this.label,
    required this.icon,
    required this.count,
    required this.highlight,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool highlight;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PetsyPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? PetsyColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? Colors.white : PetsyColors.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: selected ? Colors.white : PetsyColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.2)
                    : (highlight ? PetsyColors.warning.withValues(alpha: 0.16) : PetsyColors.mist),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11.5,
                  color: selected
                      ? Colors.white
                      : (highlight ? PetsyColors.warning : PetsyColors.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdoptionEmptyState extends StatelessWidget {
  const _AdoptionEmptyState({required this.incoming});

  final bool incoming;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
        decoration: BoxDecoration(
          color: PetsyColors.surface,
          borderRadius: BorderRadius.circular(PetsyRadius.xl),
          border: Border.all(color: PetsyColors.border),
          boxShadow: PetsyShadows.soft,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFC23A55).withValues(alpha: 0.18)),
              ),
              child: Icon(
                incoming ? Icons.inbox_outlined : Icons.send_outlined,
                size: 36,
                color: const Color(0xFFC23A55),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.t(incoming ? 'adoption_empty_incoming' : 'adoption_empty_sent'),
              textAlign: TextAlign.center,
              style: PetsyType.section.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              context.t(incoming ? 'adoption_empty_incoming_body' : 'adoption_empty_sent_body'),
              textAlign: TextAlign.center,
              style: PetsyType.meta.copyWith(height: 1.4, fontSize: 14),
            ),
            if (!incoming) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.go('/adoption'),
                  icon: const Icon(Icons.pets_rounded),
                  label: Text(context.t('adoption_browse_pets')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AdoptionRequestCard extends StatelessWidget {
  const _AdoptionRequestCard({
    required this.request,
    required this.incoming,
    required this.busy,
    required this.onAction,
  });

  final AdoptionRequest request;
  final bool incoming;
  final bool busy;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final locale = Localizations.localeOf(context).languageCode;
    final petName = r.petName ?? context.t('pet');
    final person = incoming
        ? context.t('adoption_from').replaceAll('{name}', [
            r.requesterName ?? context.t('someone'),
            if (r.requesterCity != null && r.requesterCity!.isNotEmpty) r.requesterCity!,
          ].join(' · '))
        : context.t('adoption_owner_line').replaceAll('{name}', r.ownerName ?? context.t('someone'));
    final chatWith = incoming ? r.requesterId : r.ownerId;
    final canChat = r.status == 'pending' || r.status == 'accepted';
    final pending = r.isPending;

    return Material(
      color: PetsyColors.surface,
      borderRadius: BorderRadius.circular(PetsyRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/pet/${r.petId}'),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PetsyRadius.lg),
            border: Border.all(
              color: pending && incoming
                  ? PetsyColors.warning.withValues(alpha: 0.45)
                  : PetsyColors.border,
              width: pending && incoming ? 1.3 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(width: 64, height: 64, child: NetImage(r.petImage)),
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
                                petName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PetsyType.cardTitle.copyWith(fontSize: 16),
                              ),
                            ),
                            StatusChip(r.status),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          person,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PetsyType.meta.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        if (r.createdAt != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              DateFormat.yMMMd(locale).format(r.createdAt!.toLocal()),
                              style: PetsyType.meta.copyWith(color: PetsyColors.textLight, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (r.message.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: PetsyColors.mist,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: PetsyColors.border),
                  ),
                  child: Text(
                    r.message,
                    maxLines: incoming ? 6 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: PetsyType.body.copyWith(height: 1.45, fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              if (r.closedReason == 'adopted') ...[
                const SizedBox(height: 10),
                Text(
                  context.t(incoming ? 'adoption_closed_note_owner' : 'adoption_closed_note'),
                  style: PetsyType.meta.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ],
              if (canChat) ...[
                const SizedBox(height: 12),
                if (busy)
                  const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)))
                else
                  Row(
                    children: [
                      if (incoming && r.isPending) ...[
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                            onPressed: () => onAction('accept'),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: Text(context.t('adoption_accept')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 42),
                              foregroundColor: PetsyColors.error,
                              side: BorderSide(color: PetsyColors.error.withValues(alpha: 0.5)),
                            ),
                            onPressed: () => onAction('decline'),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: Text(context.t('adoption_decline')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 42,
                          width: 42,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                            onPressed: () => openAdoptionChat(
                              context,
                              otherUserId: chatWith,
                              petId: r.petId,
                              petName: petName,
                            ),
                            child: Tooltip(
                              message: context.t('adoption_message_requester'),
                              child: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                            ),
                          ),
                        ),
                      ] else ...[
                        if (!incoming && r.isPending) ...[
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                              onPressed: () => onAction('withdraw'),
                              child: Text(context.t('adoption_withdraw')),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                            onPressed: () => openAdoptionChat(
                              context,
                              otherUserId: chatWith,
                              petId: r.petId,
                              petName: petName,
                            ),
                            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                            label: Text(
                              context.t(incoming ? 'adoption_message_requester' : 'adoption_message_owner'),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
