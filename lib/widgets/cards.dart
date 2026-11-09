import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';

class PetCard extends StatelessWidget {
  const PetCard({
    super.key,
    required this.pet,
    this.width,
    this.compact = false,
    this.showPrice = false,
    this.showGuardMeta = false,
  });

  final Pet pet;
  final double? width;

  /// Tighter padding / type for dense home carousels.
  final bool compact;

  /// Show sale price when the pet is listed for sale.
  final bool showPrice;

  /// Show guard role / country chips for the professional marketplace.
  final bool showGuardMeta;

  @override
  Widget build(BuildContext context) {
    final pad = compact ? PetsySpacing.sm + 1 : PetsySpacing.sm + 2;
    final priced = showPrice && pet.status == 'for_sale' && pet.price != null;
    final roleLabel = (pet.guardRole != null && pet.guardRole!.isNotEmpty)
        ? context.t('guard_role_${pet.guardRole}')
        : context.t('guard_dog_badge');
    final place = [
      if (pet.country != null && pet.country!.isNotEmpty) context.t('country_${pet.country}'),
      if (pet.location != null && pet.location!.trim().isNotEmpty) pet.location!.trim(),
    ].join(' · ');
    return SizedBox(
      width: width,
      child: PetsyPressScale(
        onTap: () => context.push('/pet/${pet.id}'),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(pet.image),
                    if (pet.isGuardDog)
                      PositionedDirectional(
                        top: 8,
                        start: 8,
                        child: PetsyMetaBadge(
                          label: roleLabel,
                          tone: PetsyMetaTone.accent,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(pad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            pet.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PetsyType.cardTitle.copyWith(fontSize: compact ? 14 : 15),
                          ),
                        ),
                        Icon(
                          pet.gender == 'female' ? Icons.female : Icons.male,
                          size: 18,
                          color: pet.gender == 'female' ? PetsyColors.genderFemale : PetsyColors.genderMale,
                        ),
                      ],
                    ),
                    const SizedBox(height: PetsySpacing.xs / 2),
                    Text(
                      joinIsolated(
                        [
                          pet.breed ?? context.t(pet.species),
                          if (pet.age != null && pet.age!.trim().isNotEmpty) petAgeLabel(context, pet.age),
                        ],
                        ' • ',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PetsyType.meta,
                    ),
                    if (showGuardMeta && place.isNotEmpty) ...[
                      const SizedBox(height: PetsySpacing.xs / 2),
                      Text(
                        place,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PetsyType.meta.copyWith(fontSize: 11.5),
                      ),
                    ],
                    if (priced) ...[
                      const SizedBox(height: PetsySpacing.xs),
                      Text(
                        formatPrice(pet.price!, currency: pet.currency),
                        style: PetsyType.price.copyWith(fontSize: compact ? 13 : 14),
                      ),
                    ] else if (!showGuardMeta && pet.location != null && pet.location!.isNotEmpty) ...[
                      const SizedBox(height: PetsySpacing.xs),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 14, color: PetsyColors.primary),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              pet.location!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PetsyType.meta,
                            ),
                          ),
                        ],
                      ),
                    ],
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

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.width,
    this.onAdd,
    this.onReturn,
    this.compact = false,
    this.showImageBadges = false,
    this.showBrand = false,
  });

  final Product product;
  final double? width;
  final VoidCallback? onAdd;

  /// Called after coming back from the product's page.
  final Future<void> Function()? onReturn;
  final bool compact;

  /// Discount % and out-of-stock chips on the image (shop grid).
  final bool showImageBadges;

  /// Show brand line above the product name.
  final bool showBrand;

  @override
  Widget build(BuildContext context) {
    final hasDiscount = product.originalPrice != null && product.originalPrice! > product.price;
    final pad = compact ? PetsySpacing.sm + 1 : PetsySpacing.sm + 2;
    final discountPct = hasDiscount
        ? (((product.originalPrice! - product.price) / product.originalPrice!) * 100).round()
        : null;
    return SizedBox(
      width: width,
      child: PetsyPressScale(
        onTap: () async {
          await context.push('/product/${product.id}');
          await onReturn?.call();
        },
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(product.image, icon: Icons.shopping_bag_outlined),
                    if (showImageBadges && hasDiscount && discountPct != null)
                      Positioned(
                        top: PetsySpacing.sm,
                        right: PetsySpacing.sm,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.sm, vertical: PetsySpacing.xs),
                          decoration: BoxDecoration(
                            color: PetsyColors.error,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '-$discountPct%',
                            style: PetsyType.meta.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    if (showImageBadges && !product.inStock)
                      PositionedDirectional(
                        top: PetsySpacing.sm,
                        start: PetsySpacing.sm,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.sm, vertical: PetsySpacing.xs),
                          decoration: BoxDecoration(
                            color: PetsyColors.ink.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            context.t('out_of_stock'),
                            style: PetsyType.meta.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(pad, pad, pad, compact ? pad : pad),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!compact && showBrand && product.brand != null && product.brand!.trim().isNotEmpty)
                      Text(
                        product.brand!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PetsyType.meta,
                      ),
                    Text(
                      product.name,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: PetsyType.body.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: compact ? 12.5 : 13,
                        height: 1.25,
                      ),
                    ),
                    SizedBox(height: compact ? PetsySpacing.xs : PetsySpacing.sm - 2),
                    Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  formatPrice(product.price),
                                  maxLines: 1,
                                  softWrap: false,
                                  style: PetsyType.price.copyWith(fontSize: compact ? 13 : 14),
                                ),
                                if (hasDiscount) ...[
                                  const SizedBox(width: PetsySpacing.xs),
                                  Text(
                                    formatPrice(product.originalPrice!),
                                    maxLines: 1,
                                    softWrap: false,
                                    style: PetsyType.meta.copyWith(
                                      fontSize: 11,
                                      color: PetsyColors.textLight,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (onAdd != null && product.inStock) ...[
                          const SizedBox(width: PetsySpacing.xs),
                          Material(
                            color: PetsyColors.primary,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: onAdd,
                              child: SizedBox(
                                width: compact ? 26 : 28,
                                height: compact ? 26 : 28,
                                child: const Icon(Icons.add, size: 18, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ],
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

class VetCard extends StatelessWidget {
  const VetCard({super.key, required this.vet, this.petId});

  final Vet vet;
  final String? petId;

  @override
  Widget build(BuildContext context) {
    final petQuery = (petId == null || petId!.isEmpty) ? '' : '?petId=$petId';
    final route = '/vet/${vet.id}$petQuery';
    final hasImage = vet.image != null && vet.image!.startsWith('http');
    final place = [vet.clinicName, vet.city].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · ');
    return PetsyPressScale(
      onTap: () => context.push(route),
      child: Material(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PetsyRadius.lg),
            border: Border.all(color: PetsyColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: hasImage
                          ? NetImage(vet.image, icon: Icons.medical_services_rounded)
                          : const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [PetsyColors.accentSoft, Color(0xFFD3EEE9)],
                                ),
                              ),
                              child: Icon(Icons.medical_services_rounded, color: PetsyColors.accent, size: 30),
                            ),
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
                                vet.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PetsyType.cardTitle.copyWith(fontSize: 15.5),
                              ),
                            ),
                            const SizedBox(width: 6),
                            PetsyRating(vet.rating, compact: true),
                          ],
                        ),
                        if (vet.specialty.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            vet.specialty,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PetsyType.subtitle.copyWith(
                              color: PetsyColors.accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        if (place.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined, size: 14, color: PetsyColors.textLight),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  place,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: PetsyType.meta.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (vet.experienceYears > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: PetsyColors.mist,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: PetsyColors.border),
                      ),
                      child: Text(
                        context.t('vets_years').replaceAll('{n}', '${vet.experienceYears}'),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: PetsyColors.primaryDark),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (vet.ratingCount > 0)
                    Text(
                      context.t('vet_reviews').replaceAll('{count}', '${vet.ratingCount}'),
                      style: PetsyType.meta.copyWith(fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [PetsyColors.accent, Color(0xFF1F7A6E)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.t('vet_book_short'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12.5),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_rounded, size: 15, color: Colors.white),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
