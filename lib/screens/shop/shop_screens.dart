import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../data/phone_countries.dart';
import '../../widgets/cards.dart';
import '../../widgets/city_field.dart';
import '../../widgets/common.dart';
import '../../widgets/phone_field.dart';

const productCategories = ['food', 'medicine', 'toys', 'accessories', 'shampoo', 'cages'];
const shopPetTypes = ['dog', 'cat', 'bird', 'all'];

IconData _categoryIcon(String? category) => switch (category) {
      'food' => Icons.restaurant_rounded,
      'medicine' => Icons.medical_services_outlined,
      'toys' => Icons.toys_outlined,
      'accessories' => Icons.pets_rounded,
      'shampoo' => Icons.soap_outlined,
      'cages' => Icons.home_work_outlined,
      _ => Icons.storefront_rounded,
    };

IconData _shopPetIcon(String? pet) => switch (pet) {
      'dog' => Icons.pets_rounded,
      'cat' => Icons.cruelty_free_rounded,
      'bird' => Icons.flutter_dash_rounded,
      _ => Icons.apps_rounded,
    };

IconData _shopSortIcon(_ShopSort sort) => switch (sort) {
      _ShopSort.featured => Icons.auto_awesome_rounded,
      _ShopSort.priceLow => Icons.south_rounded,
      _ShopSort.priceHigh => Icons.north_rounded,
      _ShopSort.rating => Icons.star_rounded,
    };

String _shopSortLabel(BuildContext context, _ShopSort sort) => context.t(switch (sort) {
      _ShopSort.featured => 'shop_sort_featured',
      _ShopSort.priceLow => 'guard_sort_price_low',
      _ShopSort.priceHigh => 'guard_sort_price_high',
      _ShopSort.rating => 'shop_sort_rating',
    });

enum _ShopSort { featured, priceLow, priceHigh, rating }

void _addToCart(BuildContext context, Product product) {
  context.read<CartState>().add(product);
  context.snack(context.t('added_to_cart'), success: true, icon: Icons.shopping_bag_outlined);
}

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  String? _category;
  String? _petType;
  bool _inStockOnly = false;
  bool _dealsOnly = false;
  _ShopSort _sort = _ShopSort.featured;
  final _query = TextEditingController();
  String _q = '';

  bool get _hasExtraFilters =>
      _petType != null || _inStockOnly || _dealsOnly || _sort != _ShopSort.featured;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<Product> _applyLocal(List<Product> items) {
    var list = items;
    final q = _q.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((p) {
        final hay = [p.name, p.brand ?? '', p.category, p.petType].join(' ').toLowerCase();
        return hay.contains(q);
      }).toList();
    }
    if (_petType != null && _petType != 'all') {
      list = list.where((p) => p.petType == _petType || p.petType == 'all').toList();
    }
    if (_inStockOnly) list = list.where((p) => p.inStock).toList();
    if (_dealsOnly) {
      list = list.where((p) => p.originalPrice != null && p.originalPrice! > p.price).toList();
    }
    list = [...list];
    if (_sort == _ShopSort.priceLow) {
      list.sort((a, b) => a.price.compareTo(b.price));
    } else if (_sort == _ShopSort.priceHigh) {
      list.sort((a, b) => b.price.compareTo(a.price));
    } else if (_sort == _ShopSort.rating) {
      list.sort((a, b) => b.rating.compareTo(a.rating));
    } else {
      list.sort((a, b) {
        final ad = (a.originalPrice != null && a.originalPrice! > a.price) ? 1 : 0;
        final bd = (b.originalPrice != null && b.originalPrice! > b.price) ? 1 : 0;
        final d = bd.compareTo(ad);
        return d != 0 ? d : b.rating.compareTo(a.rating);
      });
    }
    return list;
  }

  Future<void> _openFilters() async {
    final applied = await showModalBottomSheet<_ShopFilterDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ShopFiltersSheet(
        initial: _ShopFilterDraft(
          petType: _petType,
          inStockOnly: _inStockOnly,
          dealsOnly: _dealsOnly,
          sort: _sort,
        ),
      ),
    );
    if (applied != null && mounted) {
      setState(() {
        _petType = applied.petType;
        _inStockOnly = applied.inStockOnly;
        _dealsOnly = applied.dealsOnly;
        _sort = applied.sort;
      });
    }
  }

  void _clearAll() {
    _query.clear();
    setState(() {
      _q = '';
      _category = null;
      _petType = null;
      _inStockOnly = false;
      _dealsOnly = false;
      _sort = _ShopSort.featured;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartState>();
    final cartCount = cart.count;
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      appBar: AppBar(
        title: Text(context.t('shop')),
        actions: [
          IconButton(
            tooltip: context.t('shop_filters'),
            onPressed: _openFilters,
            icon: Badge(
              isLabelVisible: _hasExtraFilters,
              smallSize: 8,
              child: const Icon(Icons.tune_rounded),
            ),
          ),
          const CartButton(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: cartCount > 0
          ? _ShopCartFab(
              count: cartCount,
              total: cart.total,
              onTap: () => context.push('/cart'),
            )
          : null,
      body: AsyncView<List<Product>>(
        key: ValueKey(_category),
        loader: () => context.api.products(category: _category),
        builder: (context, items, reload) {
          final visible = _applyLocal(items);
          final deals = _category == null && _q.isEmpty && !_dealsOnly
              ? items
                  .where((p) => p.originalPrice != null && p.originalPrice! > p.price && p.inStock)
                  .take(8)
                  .toList()
              : const <Product>[];

          return RefreshIndicator(
            onRefresh: reload,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: _ShopHero()),
                SliverToBoxAdapter(
                  child: PetsySearchField(
                    controller: _query,
                    hint: context.t('shop_search_hint'),
                    margin: const EdgeInsetsDirectional.fromSTEB(
                      PetsySpacing.page,
                      PetsySpacing.md,
                      PetsySpacing.page,
                      0,
                    ),
                    onChanged: (v) => setState(() => _q = v),
                    onClear: () => setState(() => _q = ''),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(top: PetsySpacing.md),
                    child: _ShopCategorySelector(
                      selected: _category,
                      onSelected: (c) => setState(() => _category = c),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _ShopQuickFilters(
                    petType: _petType,
                    inStockOnly: _inStockOnly,
                    dealsOnly: _dealsOnly,
                    hasExtraFilters: _hasExtraFilters,
                    onOpenFilters: _openFilters,
                    onPetType: (v) => setState(() => _petType = v),
                    onToggleStock: () => setState(() => _inStockOnly = !_inStockOnly),
                    onToggleDeals: () => setState(() => _dealsOnly = !_dealsOnly),
                  ),
                ),
                if (_category != null || _petType != null || _inStockOnly || _dealsOnly || _q.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _ShopActiveFilters(
                      category: _category,
                      petType: _petType,
                      inStockOnly: _inStockOnly,
                      dealsOnly: _dealsOnly,
                      hasQuery: _q.isNotEmpty,
                      onClearCategory: () => setState(() => _category = null),
                      onClearPetType: () => setState(() => _petType = null),
                      onClearStock: () => setState(() => _inStockOnly = false),
                      onClearDeals: () => setState(() => _dealsOnly = false),
                      onClearQuery: () {
                        _query.clear();
                        setState(() => _q = '');
                      },
                      onClearAll: _clearAll,
                    ),
                  ),
                if (deals.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        PetsySpacing.page,
                        PetsySpacing.lg,
                        PetsySpacing.page,
                        PetsySpacing.sm,
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(context.t('shop_deals'), style: PetsyType.section)),
                          TextButton(
                            onPressed: () => setState(() => _dealsOnly = true),
                            child: Text(context.t('see_all')),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 228,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.page),
                        itemCount: deals.length,
                        separatorBuilder: (_, _) => const SizedBox(width: PetsySpacing.md),
                        itemBuilder: (_, i) => ProductCard(
                          product: deals[i],
                          width: 148,
                          compact: true,
                          showImageBadges: true,
                          onAdd: deals[i].inStock ? () => _addToCart(context, deals[i]) : null,
                        ),
                      ),
                    ),
                  ),
                ],
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      PetsySpacing.page,
                      PetsySpacing.md,
                      PetsySpacing.page,
                      PetsySpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            visible.length == 1
                                ? context.t('shop_results_one')
                                : context.t('shop_results').replaceAll('{count}', '${visible.length}'),
                            style: PetsyType.meta.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        _ShopSortChip(
                          label: _shopSortLabel(context, _sort),
                          icon: _shopSortIcon(_sort),
                          active: _sort != _ShopSort.featured || _hasExtraFilters,
                          onTap: _openFilters,
                        ),
                      ],
                    ),
                  ),
                ),
                if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: MessageView(
                      icon: Icons.storefront_outlined,
                      text: '${context.t('shop_empty_title')}\n${context.t('shop_empty_body')}',
                      action: TextButton(onPressed: _clearAll, child: Text(context.t('clear'))),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      PetsySpacing.page,
                      0,
                      PetsySpacing.page,
                      cartCount > 0 ? 118 : PetsySpacing.listBottom,
                    ),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisExtent: 268,
                        crossAxisSpacing: PetsySpacing.md,
                        mainAxisSpacing: PetsySpacing.md,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => ProductCard(
                          product: visible[i],
                          showImageBadges: true,
                          showBrand: true,
                          onAdd: visible[i].inStock ? () => _addToCart(context, visible[i]) : null,
                        ),
                        childCount: visible.length,
                      ),
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

class _ShopCartFab extends StatelessWidget {
  const _ShopCartFab({
    required this.count,
    required this.total,
    required this.onTap,
  });

  final int count;
  final double total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final countLabel = count == 1
        ? context.t('cart_items_count_one')
        : context.t('cart_items_count').replaceAll('{count}', '$count');

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.page),
        child: PetsyPressScale(
          onTap: onTap,
          scale: 0.98,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFD44318),
                  PetsyColors.primary,
                  PetsyColors.secondary,
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: PetsyShadows.fab,
            ),
            padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                      ),
                      child: const Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 22),
                    ),
                    PositionedDirectional(
                      top: -5,
                      end: -5,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(99),
                          boxShadow: PetsyShadows.soft,
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: const TextStyle(
                            color: PetsyColors.primaryDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.t('cart_fab_view'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        countLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatPrice(total),
                        style: const TextStyle(
                          color: PetsyColors.primaryDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const PetsyChevron.forward(size: 14, color: PetsyColors.primaryDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShopHero extends StatefulWidget {
  const _ShopHero();

  @override
  State<_ShopHero> createState() => _ShopHeroState();
}

class _ShopHeroState extends State<_ShopHero> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2300),
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
                  begin: Alignment(-1 + t * 0.25, -1),
                  end: Alignment(1, 1 - t * 0.2),
                  colors: const [
                    Color(0xFFD44318),
                    Color(0xFFFF5C2E),
                    Color(0xFFFF8F63),
                  ],
                ),
              ),
              child: child,
            );
          },
          child: Stack(
            children: [
              Positioned(
                right: -24,
                top: -18,
                child: Icon(Icons.shopping_bag_rounded, size: 130, color: Colors.white.withValues(alpha: 0.1)),
              ),
              Positioned(
                left: -20,
                bottom: -26,
                child: Icon(Icons.pets_rounded, size: 100, color: Colors.white.withValues(alpha: 0.08)),
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
                        context.t('shop_hero_tag'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.t('shop_hero_title'),
                      style: PetsyType.title.copyWith(color: Colors.white, fontSize: 22, height: 1.2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t('shop_subtitle'),
                      style: PetsyType.meta.copyWith(color: Colors.white.withValues(alpha: 0.88), height: 1.4, fontSize: 13.5),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _ShopHeroChip(icon: Icons.restaurant_rounded, label: context.t('food')),
                        const SizedBox(width: 8),
                        _ShopHeroChip(icon: Icons.toys_outlined, label: context.t('toys')),
                        const SizedBox(width: 8),
                        _ShopHeroChip(icon: Icons.local_offer_rounded, label: context.t('shop_deals')),
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

class _ShopHeroChip extends StatelessWidget {
  const _ShopHeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopCategorySelector extends StatelessWidget {
  const _ShopCategorySelector({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 102,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.page),
        itemCount: productCategories.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          if (i == 0) {
            return _ShopCatTile(
              icon: Icons.apps_rounded,
              label: context.t('all'),
              selected: selected == null,
              onTap: () => onSelected(null),
            );
          }
          final cat = productCategories[i - 1];
          return _ShopCatTile(
            icon: _categoryIcon(cat),
            label: context.t(cat),
            selected: selected == cat,
            onTap: () => onSelected(cat),
          );
        },
      ),
    );
  }
}

class _ShopCatTile extends StatelessWidget {
  const _ShopCatTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PetsyPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 86,
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [PetsyColors.primary, PetsyColors.secondary],
                )
              : null,
          color: selected ? null : PetsyColors.surface,
          borderRadius: BorderRadius.circular(PetsyRadius.lg),
          border: Border.all(
            color: selected ? Colors.transparent : PetsyColors.border,
          ),
          boxShadow: selected ? PetsyShadows.soft : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.22) : PetsyColors.mist,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: selected ? Colors.white : PetsyColors.primaryDark, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : PetsyColors.text,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopQuickFilters extends StatelessWidget {
  const _ShopQuickFilters({
    required this.petType,
    required this.inStockOnly,
    required this.dealsOnly,
    required this.hasExtraFilters,
    required this.onOpenFilters,
    required this.onPetType,
    required this.onToggleStock,
    required this.onToggleDeals,
  });

  final String? petType;
  final bool inStockOnly;
  final bool dealsOnly;
  final bool hasExtraFilters;
  final VoidCallback onOpenFilters;
  final ValueChanged<String?> onPetType;
  final VoidCallback onToggleStock;
  final VoidCallback onToggleDeals;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, PetsySpacing.md, 0, 0),
      child: SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.page),
          children: [
            _ShopQuickChip(
              icon: Icons.tune_rounded,
              label: context.t('shop_filters'),
              selected: hasExtraFilters,
              emphasize: true,
              onTap: onOpenFilters,
            ),
            const SizedBox(width: 8),
            _ShopQuickChip(
              icon: Icons.local_offer_rounded,
              label: context.t('shop_deals'),
              selected: dealsOnly,
              onTap: onToggleDeals,
            ),
            const SizedBox(width: 8),
            _ShopQuickChip(
              icon: Icons.inventory_2_outlined,
              label: context.t('shop_in_stock'),
              selected: inStockOnly,
              onTap: onToggleStock,
            ),
            const SizedBox(width: 8),
            for (final p in shopPetTypes.where((e) => e != 'all')) ...[
              _ShopQuickChip(
                icon: _shopPetIcon(p),
                label: context.t(p),
                selected: petType == p,
                onTap: () => onPetType(petType == p ? null : p),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShopQuickChip extends StatelessWidget {
  const _ShopQuickChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.emphasize = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? PetsyColors.primary
        : emphasize
            ? PetsyColors.mist
            : PetsyColors.surface;
    final fg = selected ? Colors.white : PetsyColors.text;
    final iconColor = selected ? Colors.white : PetsyColors.primaryDark;
    return PetsyPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected
                ? PetsyColors.primary
                : emphasize
                    ? PetsyColors.primary.withValues(alpha: 0.28)
                    : PetsyColors.border,
          ),
          boxShadow: selected ? PetsyShadows.soft : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopSortChip extends StatelessWidget {
  const _ShopSortChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PetsyPressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? PetsyColors.primarySoft : PetsyColors.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: active ? PetsyColors.primary.withValues(alpha: 0.35) : PetsyColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: PetsyColors.primaryDark),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: PetsyColors.text,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: PetsyColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _ShopActiveFilters extends StatelessWidget {
  const _ShopActiveFilters({
    required this.category,
    required this.petType,
    required this.inStockOnly,
    required this.dealsOnly,
    required this.hasQuery,
    required this.onClearCategory,
    required this.onClearPetType,
    required this.onClearStock,
    required this.onClearDeals,
    required this.onClearQuery,
    required this.onClearAll,
  });

  final String? category;
  final String? petType;
  final bool inStockOnly;
  final bool dealsOnly;
  final bool hasQuery;
  final VoidCallback onClearCategory;
  final VoidCallback onClearPetType;
  final VoidCallback onClearStock;
  final VoidCallback onClearDeals;
  final VoidCallback onClearQuery;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(PetsySpacing.page, PetsySpacing.md, PetsySpacing.page, 0),
      child: Row(
        children: [
          if (category != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _ShopFilterChip(
                icon: _categoryIcon(category),
                label: context.t(category!),
                onDeleted: onClearCategory,
              ),
            ),
          if (petType != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _ShopFilterChip(
                icon: _shopPetIcon(petType),
                label: context.t(petType!),
                onDeleted: onClearPetType,
              ),
            ),
          if (inStockOnly)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _ShopFilterChip(
                icon: Icons.inventory_2_outlined,
                label: context.t('shop_in_stock_only'),
                onDeleted: onClearStock,
              ),
            ),
          if (dealsOnly)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _ShopFilterChip(
                icon: Icons.local_offer_rounded,
                label: context.t('shop_deals_only'),
                onDeleted: onClearDeals,
              ),
            ),
          if (hasQuery)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _ShopFilterChip(
                icon: Icons.search_rounded,
                label: context.t('guard_dogs_search_active'),
                onDeleted: onClearQuery,
              ),
            ),
          PetsyPressScale(
            onTap: onClearAll,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: PetsyColors.shellWash,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: PetsyColors.border),
              ),
              child: Text(
                context.t('clear_all'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: PetsyColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopFilterChip extends StatelessWidget {
  const _ShopFilterChip({
    required this.label,
    required this.onDeleted,
    this.icon,
  });

  final String label;
  final VoidCallback onDeleted;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 6, 7),
      decoration: BoxDecoration(
        color: PetsyColors.primarySoft,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: PetsyColors.primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: PetsyColors.primaryDark),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: PetsyColors.primaryDark,
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: onDeleted,
            borderRadius: BorderRadius.circular(99),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close_rounded, size: 15, color: PetsyColors.primaryDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopFilterDraft {
  const _ShopFilterDraft({
    required this.petType,
    required this.inStockOnly,
    required this.dealsOnly,
    required this.sort,
  });

  final String? petType;
  final bool inStockOnly;
  final bool dealsOnly;
  final _ShopSort sort;
}

class _ShopFiltersSheet extends StatefulWidget {
  const _ShopFiltersSheet({required this.initial});

  final _ShopFilterDraft initial;

  @override
  State<_ShopFiltersSheet> createState() => _ShopFiltersSheetState();
}

class _ShopFiltersSheetState extends State<_ShopFiltersSheet> {
  late String? _petType = widget.initial.petType;
  late bool _inStockOnly = widget.initial.inStockOnly;
  late bool _dealsOnly = widget.initial.dealsOnly;
  late _ShopSort _sort = widget.initial.sort;

  int get _activeCount {
    var n = 0;
    if (_petType != null) n++;
    if (_inStockOnly) n++;
    if (_dealsOnly) n++;
    if (_sort != _ShopSort.featured) n++;
    return n;
  }

  void _reset() {
    setState(() {
      _petType = null;
      _inStockOnly = false;
      _dealsOnly = false;
      _sort = _ShopSort.featured;
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Material(
            color: PetsyColors.backgroundAlt,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(PetsyRadius.xl)),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: PetsyColors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      PetsySpacing.page,
                      PetsySpacing.lg,
                      PetsySpacing.page,
                      PetsySpacing.md,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: PetsyColors.primarySoft,
                            borderRadius: BorderRadius.circular(PetsyRadius.md),
                          ),
                          child: const Icon(Icons.tune_rounded, color: PetsyColors.primaryDark),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(context.t('shop_filters'), style: PetsyType.section),
                              const SizedBox(height: 2),
                              Text(
                                context.t('shop_filters_subtitle'),
                                style: PetsyType.meta.copyWith(height: 1.3),
                              ),
                            ],
                          ),
                        ),
                        if (_activeCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: PetsyColors.primary,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '$_activeCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        PetsySpacing.page,
                        0,
                        PetsySpacing.page,
                        PetsySpacing.md,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ShopFilterSection(
                            title: context.t('shop_pet_type'),
                            icon: Icons.pets_rounded,
                            child: Row(
                              children: [
                                Expanded(
                                  child: _ShopPetOption(
                                    icon: _shopPetIcon(null),
                                    label: context.t('all'),
                                    selected: _petType == null,
                                    onTap: () => setState(() => _petType = null),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                for (final p in shopPetTypes.where((e) => e != 'all')) ...[
                                  Expanded(
                                    child: _ShopPetOption(
                                      icon: _shopPetIcon(p),
                                      label: context.t(p),
                                      selected: _petType == p,
                                      onTap: () => setState(() => _petType = p),
                                    ),
                                  ),
                                  if (p != 'bird') const SizedBox(width: 8),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: PetsySpacing.md),
                          _ShopFilterSection(
                            title: context.t('shop_sort'),
                            icon: Icons.sort_rounded,
                            child: Column(
                              children: [
                                for (var i = 0; i < _ShopSort.values.length; i++) ...[
                                  if (i > 0) const SizedBox(height: 8),
                                  _ShopSortOption(
                                    icon: _shopSortIcon(_ShopSort.values[i]),
                                    label: _shopSortLabel(context, _ShopSort.values[i]),
                                    selected: _sort == _ShopSort.values[i],
                                    onTap: () => setState(() => _sort = _ShopSort.values[i]),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: PetsySpacing.md),
                          _ShopFilterSection(
                            title: context.t('shop_availability'),
                            icon: Icons.inventory_2_outlined,
                            child: Column(
                              children: [
                                _ShopToggleCard(
                                  icon: Icons.check_circle_outline_rounded,
                                  title: context.t('shop_in_stock_only'),
                                  subtitle: context.t('shop_in_stock_hint'),
                                  value: _inStockOnly,
                                  onChanged: (v) => setState(() => _inStockOnly = v),
                                ),
                                const SizedBox(height: 8),
                                _ShopToggleCard(
                                  icon: Icons.local_offer_outlined,
                                  title: context.t('shop_deals_only'),
                                  subtitle: context.t('shop_deals_hint'),
                                  value: _dealsOnly,
                                  accent: PetsyColors.accent,
                                  accentSoft: PetsyColors.accentSoft,
                                  onChanged: (v) => setState(() => _dealsOnly = v),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(
                      PetsySpacing.page,
                      PetsySpacing.md,
                      PetsySpacing.page,
                      PetsySpacing.page,
                    ),
                    decoration: BoxDecoration(
                      color: PetsyColors.surface,
                      border: Border(top: BorderSide(color: PetsyColors.border.withValues(alpha: 0.8))),
                      boxShadow: PetsyShadows.soft,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _reset,
                            child: Text(context.t('clear')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: () => Navigator.pop(
                              context,
                              _ShopFilterDraft(
                                petType: _petType,
                                inStockOnly: _inStockOnly,
                                dealsOnly: _dealsOnly,
                                sort: _sort,
                              ),
                            ),
                            child: Text(context.t('guard_filters_apply')),
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
      ),
    );
  }
}

class _ShopFilterSection extends StatelessWidget {
  const _ShopFilterSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        border: Border.all(color: PetsyColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: PetsyColors.primaryDark),
              const SizedBox(width: 7),
              Text(
                title,
                style: PetsyType.meta.copyWith(
                  fontWeight: FontWeight.w800,
                  color: PetsyColors.text,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ShopPetOption extends StatelessWidget {
  const _ShopPetOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PetsyPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? PetsyColors.primarySoft : PetsyColors.backgroundAlt,
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          border: Border.all(
            color: selected ? PetsyColors.primary : PetsyColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: selected ? PetsyColors.primaryDark : PetsyColors.textSecondary),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                color: selected ? PetsyColors.primaryDark : PetsyColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopSortOption extends StatelessWidget {
  const _ShopSortOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PetsyPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? PetsyColors.primarySoft : PetsyColors.backgroundAlt,
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          border: Border.all(
            color: selected ? PetsyColors.primary : PetsyColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: selected ? PetsyColors.primary : PetsyColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 17,
                color: selected ? Colors.white : PetsyColors.primaryDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: selected ? PetsyColors.primaryDark : PetsyColors.text,
                ),
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 20,
              color: selected ? PetsyColors.primary : PetsyColors.textLight,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopToggleCard extends StatelessWidget {
  const _ShopToggleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.accent = PetsyColors.primary,
    this.accentSoft = PetsyColors.primarySoft,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color accent;
  final Color accentSoft;

  @override
  Widget build(BuildContext context) {
    return PetsyPressScale(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        decoration: BoxDecoration(
          color: value ? accentSoft : PetsyColors.backgroundAlt,
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          border: Border.all(
            color: value ? accent.withValues(alpha: 0.55) : PetsyColors.border,
            width: value ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: value ? accent : PetsyColors.surface,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 18, color: value ? Colors.white : PetsyColors.primaryDark),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: value ? accent == PetsyColors.accent ? PetsyColors.accent : PetsyColors.primaryDark : PetsyColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: PetsyType.meta.copyWith(fontSize: 11.5, height: 1.25),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              activeThumbColor: accent,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  bool _favorite = false;
  bool _savingFavorite = false;

  Future<Product> _load() async {
    final api = context.api;
    final loggedIn = context.read<AuthState>().isLoggedIn;
    final favorite = loggedIn ? api.isProductFavorite(widget.productId) : Future.value(false);
    final product = await api.product(widget.productId);
    _favorite = await favorite.catchError((_) => false);
    return product;
  }

  Future<void> _toggleFavorite(Product product) async {
    if (!context.requireLogin() || _savingFavorite) return;
    final next = !_favorite;
    setState(() {
      _favorite = next;
      _savingFavorite = true;
    });
    try {
      await context.api.setProductFavorite(product.id, next);
      if (mounted) {
        context.snack(
          context.t(next ? 'favorite_added' : 'favorite_removed'),
          success: next,
          icon: next ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _favorite = !next);
        context.snack(context.errorText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _savingFavorite = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PetsyColors.backgroundAlt,
      body: AsyncView<Product>(
        loader: _load,
        builder: (context, product, _) {
          final hasDiscount = product.originalPrice != null && product.originalPrice! > product.price;
          return Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      expandedHeight: 340,
                      pinned: true,
                      backgroundColor: PetsyColors.background,
                      leading: IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.92),
                        ),
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                      ),
                      actions: [
                        IconButton(
                          style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.92)),
                          tooltip: context.t(_favorite ? 'favorite_remove' : 'favorite_add'),
                          onPressed: _savingFavorite ? null : () => _toggleFavorite(product),
                          icon: Icon(
                            _favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: PetsyColors.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        CartButton(
                          style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.92)),
                        ),
                        const SizedBox(width: 8),
                      ],
                      flexibleSpace: FlexibleSpaceBar(
                        background: Stack(
                          fit: StackFit.expand,
                          children: [
                            NetImage(product.image, icon: Icons.shopping_bag_outlined),
                            if ((product.image ?? '').isNotEmpty)
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x33000000),
                                    Color(0x00000000),
                                    Color(0x55000000),
                                  ],
                                  stops: [0, 0.5, 1],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 16,
                              right: 16,
                              bottom: 18,
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: product.inStock
                                          ? PetsyColors.accentSoft
                                          : Colors.black.withValues(alpha: 0.65),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Text(
                                      context.t(product.inStock ? 'shop_in_stock' : 'out_of_stock'),
                                      style: TextStyle(
                                        color: product.inStock ? PetsyColors.accent : Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  if (hasDiscount) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: PetsyColors.error,
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                        '-${(((product.originalPrice! - product.price) / product.originalPrice!) * 100).round()}%',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (product.brand != null && product.brand!.trim().isNotEmpty)
                              Text(
                                product.brand!,
                                style: const TextStyle(
                                  color: PetsyColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              product.name,
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.15),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Text(
                                  formatPrice(product.price),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: PetsyColors.primary,
                                  ),
                                ),
                                if (hasDiscount) ...[
                                  const SizedBox(width: 10),
                                  Text(
                                    formatPrice(product.originalPrice!),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: PetsyColors.textLight,
                                      decoration: TextDecoration.lineThrough,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                PetsyRating(product.rating),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                              decoration: BoxDecoration(
                                color: PetsyColors.mist,
                                borderRadius: BorderRadius.circular(PetsyRadius.lg),
                              ),
                              child: Text(
                                context.t('buy_now_hint'),
                                style: const TextStyle(
                                  color: PetsyColors.primaryDark,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              context.t('product_info'),
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _ProductInfoTile(
                                    icon: _categoryIcon(product.category),
                                    label: context.t('category'),
                                    value: context.t(product.category),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _ProductInfoTile(
                                    icon: Icons.pets_rounded,
                                    label: context.t('product_for'),
                                    value: context.t(product.petType),
                                  ),
                                ),
                              ],
                            ),
                            if (product.description != null && product.description!.trim().isNotEmpty) ...[
                              const SizedBox(height: 20),
                              Text(
                                context.t('product_about'),
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: PetsyColors.surface,
                                  borderRadius: BorderRadius.circular(PetsyRadius.lg),
                                  border: Border.all(color: PetsyColors.border),
                                ),
                                child: Text(
                                  product.description!,
                                  style: const TextStyle(height: 1.55, fontSize: 14.5),
                                ),
                              ),
                            ],
                            const SizedBox(height: 88),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              BottomActionBar(
                child: FilledButton.icon(
                  onPressed: product.inStock ? () => _addToCart(context, product) : null,
                  icon: Icon(product.inStock ? Icons.add_shopping_cart_rounded : Icons.remove_shopping_cart_outlined),
                  label: Text(context.t(product.inStock ? 'add_to_cart' : 'out_of_stock')),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductInfoTile extends StatelessWidget {
  const _ProductInfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        border: Border.all(color: PetsyColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: PetsyColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: PetsyColors.primaryDark),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: PetsyColors.textSecondary,
                    fontWeight: FontWeight.w600,
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

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  Future<void> _confirmClear(BuildContext context, CartState cart) async {
    final ok = await confirmAction(
      context,
      title: context.t('cart_clear'),
      message: context.t('cart_clear_confirm'),
      confirmLabel: context.t('cart_clear'),
      icon: Icons.remove_shopping_cart_outlined,
    );
    if (ok) cart.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartState>();
    final empty = cart.items.isEmpty;
    final countLabel = cart.count == 1
        ? context.t('cart_items_count_one')
        : context.t('cart_items_count').replaceAll('{count}', '${cart.count}');

    return PetsyPage(
      appBar: AppBar(
        title: Text(context.t('cart')),
        actions: [
          if (!empty)
            IconButton(
              tooltip: context.t('cart_clear'),
              onPressed: () => _confirmClear(context, cart),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      bottomNavigationBar: empty
          ? null
          : _CartCheckoutBar(
              total: cart.total,
              countLabel: countLabel,
              onCheckout: () {
                if (context.requireLogin()) context.push('/checkout');
              },
            ),
      child: empty
          ? const _CartEmptyState()
          : CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: _CartHero()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      PetsySpacing.page,
                      PetsySpacing.md,
                      PetsySpacing.page,
                      PetsySpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            countLabel,
                            style: PetsyType.meta.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => context.go('/shop'),
                          icon: const Icon(Icons.storefront_outlined, size: 18),
                          label: Text(
                            context.t('cart_continue_shopping'),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    PetsySpacing.page,
                    0,
                    PetsySpacing.page,
                    PetsySpacing.md,
                  ),
                  sliver: SliverList.separated(
                    itemCount: cart.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final item = cart.items[i];
                      return _CartItemCard(
                        item: item,
                        onOpen: () => context.push('/product/${item.productId}'),
                        onInc: () => cart.setQuantity(item.productId, item.quantity + 1),
                        onDec: () => cart.setQuantity(item.productId, item.quantity - 1),
                        onRemove: () => cart.setQuantity(item.productId, 0),
                      );
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      PetsySpacing.page,
                      0,
                      PetsySpacing.page,
                      PetsySpacing.listBottom,
                    ),
                    child: _CartSummaryCard(total: cart.total, countLabel: countLabel),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CartHero extends StatefulWidget {
  const _CartHero();

  @override
  State<_CartHero> createState() => _CartHeroState();
}

class _CartHeroState extends State<_CartHero> with SingleTickerProviderStateMixin {
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
                    Color(0xFFD44318),
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
                right: -20,
                top: -14,
                child: Icon(Icons.shopping_bag_rounded, size: 118, color: Colors.white.withValues(alpha: 0.12)),
              ),
              Positioned(
                left: -18,
                bottom: -24,
                child: Icon(Icons.pets_rounded, size: 90, color: Colors.white.withValues(alpha: 0.08)),
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
                        context.t('cart_hero_tag'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.t('cart_hero_title'),
                      style: PetsyType.title.copyWith(color: Colors.white, fontSize: 22, height: 1.2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t('cart_subtitle'),
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

class _CartEmptyState extends StatelessWidget {
  const _CartEmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(PetsySpacing.page, PetsySpacing.xl, PetsySpacing.page, PetsySpacing.listBottom),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
          decoration: BoxDecoration(
            color: PetsyColors.surface,
            borderRadius: BorderRadius.circular(PetsyRadius.xl),
            border: Border.all(color: PetsyColors.border),
            boxShadow: PetsyShadows.soft,
          ),
          child: Column(
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: PetsyColors.primarySoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: PetsyColors.primary.withValues(alpha: 0.18)),
                ),
                child: const Icon(Icons.shopping_bag_outlined, size: 36, color: PetsyColors.primaryDark),
              ),
              const SizedBox(height: 16),
              Text(context.t('cart_empty_title'), style: PetsyType.section.copyWith(fontSize: 18)),
              const SizedBox(height: 8),
              Text(
                context.t('cart_empty_body'),
                textAlign: TextAlign.center,
                style: PetsyType.meta.copyWith(height: 1.4, fontSize: 14),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.go('/shop'),
                  icon: const Icon(Icons.storefront_rounded),
                  label: Text(context.t('cart_browse_shop')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CartSummaryCard extends StatelessWidget {
  const _CartSummaryCard({required this.total, required this.countLabel});

  final double total;
  final String countLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        border: Border.all(color: PetsyColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, size: 18, color: PetsyColors.primaryDark),
              const SizedBox(width: 8),
              Text(context.t('cart_summary'), style: PetsyType.meta.copyWith(fontWeight: FontWeight.w800, color: PetsyColors.text)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Text(countLabel, style: PetsyType.meta.copyWith(fontWeight: FontWeight.w700))),
              Text(
                formatPrice(total),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: PetsyColors.primaryDark),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CartCheckoutBar extends StatelessWidget {
  const _CartCheckoutBar({
    required this.total,
    required this.countLabel,
    required this.onCheckout,
  });

  final double total;
  final String countLabel;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PetsyColors.surface,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(PetsySpacing.page, PetsySpacing.md, PetsySpacing.page, PetsySpacing.md),
          decoration: BoxDecoration(
            border: const Border(top: BorderSide(color: PetsyColors.border)),
            boxShadow: PetsyShadows.soft,
          ),
          child: PetsyPressScale(
            onTap: onCheckout,
            scale: 0.98,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFD44318), PetsyColors.primary, PetsyColors.secondary],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: PetsyColors.primary.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.shopping_cart_checkout_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.t('cart_checkout_cta'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          countLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      formatPrice(total),
                      style: const TextStyle(
                        color: PetsyColors.primaryDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  const _CartItemCard({
    required this.item,
    required this.onOpen,
    required this.onInc,
    required this.onDec,
    required this.onRemove,
  });

  final CartItem item;
  final VoidCallback onOpen;
  final VoidCallback onInc;
  final VoidCallback onDec;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final lineTotal = item.price * item.quantity;

    return Material(
      color: PetsyColors.surface,
      borderRadius: BorderRadius.circular(PetsyRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PetsyRadius.lg),
            border: Border.all(color: PetsyColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(PetsyRadius.md),
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: NetImage(item.image, icon: Icons.shopping_bag_outlined),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: PetsyType.cardTitle.copyWith(height: 1.25),
                          ),
                        ),
                        const SizedBox(width: 4),
                        PetsyPressScale(
                          onTap: onRemove,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: PetsyColors.shellWash,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.close_rounded, size: 16, color: PetsyColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${context.t('cart_unit_price')}: ${formatPrice(item.price)}',
                      style: PetsyType.meta.copyWith(fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: PetsyColors.backgroundAlt,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: PetsyColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _QtyButton(icon: Icons.remove_rounded, onTap: onDec),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Text(
                                  '${item.quantity}',
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
                                ),
                              ),
                              _QtyButton(
                                icon: Icons.add_rounded,
                                onTap: onInc,
                                filled: true,
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          formatPrice(lineTotal),
                          style: const TextStyle(
                            color: PetsyColors.primaryDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 15.5,
                          ),
                        ),
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

class _QtyButton extends StatelessWidget {
  const _QtyButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? PetsyColors.primary : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            icon,
            size: 17,
            color: filled ? Colors.white : PetsyColors.text,
          ),
        ),
      ),
    );
  }
}

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _form = GlobalKey<FormState>();
  final _phoneKey = GlobalKey<PetsyPhoneFieldState>();
  late final ParsedPhone _parsedPhone = parseStoredPhone(context.read<AuthState>().user?.phone);
  late final _city = TextEditingController(text: context.read<AuthState>().user?.city ?? '');
  late final _phone = TextEditingController(text: _parsedPhone.national);
  final _address = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;

  @override
  void dispose() {
    _city.dispose();
    _phone.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) {
      setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
      return;
    }
    final cart = context.read<CartState>();
    if (cart.items.isEmpty) {
      context.snack(context.t('checkout_empty_cart'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final order = await context.api.createOrder(
        items: cart.items,
        total: cart.total,
        address: _address.text.trim(),
        city: _city.text.trim(),
        phone: _phoneKey.currentState?.completeNumber ?? _phone.text.trim(),
        notes: _notes.text.trim(),
      );
      cart.clear();
      if (!mounted) return;
      context.go('/order-success', extra: order);
    } catch (e) {
      if (mounted) context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartState>();
    String? required(String? v) => (v == null || v.trim().isEmpty) ? context.t('required') : null;
    final countLabel = cart.count == 1
        ? context.t('cart_items_count_one')
        : context.t('cart_items_count').replaceAll('{count}', '${cart.count}');

    if (cart.items.isEmpty) {
      return PetsyPage(
        appBar: AppBar(title: Text(context.t('checkout'))),
        child: const _CheckoutEmptyState(),
      );
    }

    return PetsyPage(
      appBar: AppBar(title: Text(context.t('checkout'))),
      bottomNavigationBar: _CheckoutPlaceBar(
        total: cart.total,
        countLabel: countLabel,
        busy: _busy,
        onPlace: _submit,
      ),
      child: Form(
        key: _form,
        autovalidateMode: _autovalidate,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            PetsySpacing.page,
            PetsySpacing.md,
            PetsySpacing.page,
            PetsySpacing.listBottom,
          ),
          children: [
            const _CheckoutHero(),
            const SizedBox(height: 14),
            const _CheckoutSteps(current: 1),
            const SizedBox(height: 16),
            _CheckoutSummaryCard(items: cart.items, total: cart.total),
            const SizedBox(height: 12),
            SectionCard(
              title: context.t('checkout_shipping_section'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t('checkout_shipping_hint'),
                    style: PetsyType.meta.copyWith(fontWeight: FontWeight.w600, height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _address,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: context.t('shipping_address'),
                      prefixIcon: const Icon(Icons.home_outlined),
                    ),
                    validator: required,
                  ),
                  const SizedBox(height: 14),
                  PetsyCityField(
                    controller: _city,
                    label: context.t('city'),
                    required: true,
                    autofillFromGps: _city.text.trim().isEmpty,
                    validator: required,
                  ),
                  const SizedBox(height: 14),
                  PetsyPhoneField(
                    key: _phoneKey,
                    controller: _phone,
                    required: true,
                    initialCountryIso: _parsedPhone.country.iso,
                    decoration: InputDecoration(labelText: context.t('phone')),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _notes,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: context.t('notes'),
                      alignLabelWithHint: true,
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(bottom: 48),
                        child: Icon(Icons.notes_outlined),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: context.t('payment_method'),
              child: const _CheckoutCodCard(),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: PetsyColors.mist,
                borderRadius: BorderRadius.circular(PetsyRadius.lg),
                border: Border.all(color: PetsyColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_outlined, size: 18, color: PetsyColors.primaryDark),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.t('checkout_trust'),
                      style: PetsyType.meta.copyWith(fontWeight: FontWeight.w700, color: PetsyColors.text),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 96),
          ],
        ),
      ),
    );
  }
}

class _CheckoutHero extends StatefulWidget {
  const _CheckoutHero();

  @override
  State<_CheckoutHero> createState() => _CheckoutHeroState();
}

class _CheckoutHeroState extends State<_CheckoutHero> with SingleTickerProviderStateMixin {
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
    return ClipRRect(
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
                  Color(0xFFD44318),
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
              child: Icon(Icons.local_shipping_rounded, size: 110, color: Colors.white.withValues(alpha: 0.12)),
            ),
            Positioned(
              left: -16,
              bottom: -22,
              child: Icon(Icons.pets_rounded, size: 84, color: Colors.white.withValues(alpha: 0.08)),
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
                      context.t('checkout_hero_tag'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.t('checkout_hero_title'),
                    style: PetsyType.title.copyWith(color: Colors.white, fontSize: 22, height: 1.2),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.t('checkout_subtitle'),
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
    );
  }
}

class _CheckoutEmptyState extends StatelessWidget {
  const _CheckoutEmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(PetsySpacing.page, PetsySpacing.xl, PetsySpacing.page, PetsySpacing.listBottom),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
          decoration: BoxDecoration(
            color: PetsyColors.surface,
            borderRadius: BorderRadius.circular(PetsyRadius.xl),
            border: Border.all(color: PetsyColors.border),
            boxShadow: PetsyShadows.soft,
          ),
          child: Column(
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: PetsyColors.primarySoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: PetsyColors.primary.withValues(alpha: 0.18)),
                ),
                child: const Icon(Icons.shopping_cart_outlined, size: 36, color: PetsyColors.primaryDark),
              ),
              const SizedBox(height: 16),
              Text(context.t('checkout_empty_title'), style: PetsyType.section.copyWith(fontSize: 18)),
              const SizedBox(height: 8),
              Text(
                context.t('checkout_empty_cart'),
                textAlign: TextAlign.center,
                style: PetsyType.meta.copyWith(height: 1.4, fontSize: 14),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.go('/shop'),
                  icon: const Icon(Icons.storefront_rounded),
                  label: Text(context.t('cart_browse_shop')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CheckoutSummaryCard extends StatelessWidget {
  const _CheckoutSummaryCard({required this.items, required this.total});

  final List<CartItem> items;
  final double total;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: context.t('checkout_summary'),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 18, color: PetsyColors.border),
            _CheckoutSummaryRow(item: items[i]),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: PetsyColors.mist,
              borderRadius: BorderRadius.circular(PetsyRadius.md),
            ),
            child: Row(
              children: [
                Text(context.t('total'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const Spacer(),
                Text(
                  formatPrice(total),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: PetsyColors.primaryDark,
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

class _CheckoutCodCard extends StatelessWidget {
  const _CheckoutCodCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            PetsyColors.accentSoft,
            PetsyColors.mist,
            Colors.white.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        border: Border.all(color: PetsyColors.accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(14),
              boxShadow: PetsyShadows.soft,
            ),
            child: const Icon(Icons.payments_rounded, color: PetsyColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t('cash_on_delivery'),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
                const SizedBox(height: 3),
                Text(
                  context.t('checkout_cod_hint'),
                  style: PetsyType.meta.copyWith(fontWeight: FontWeight.w600, height: 1.3),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: PetsyColors.accent,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  context.t('checkout_cod_selected'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutPlaceBar extends StatelessWidget {
  const _CheckoutPlaceBar({
    required this.total,
    required this.countLabel,
    required this.busy,
    required this.onPlace,
  });

  final double total;
  final String countLabel;
  final bool busy;
  final VoidCallback onPlace;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PetsyColors.surface,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(PetsySpacing.page, PetsySpacing.md, PetsySpacing.page, PetsySpacing.md),
          decoration: BoxDecoration(
            border: const Border(top: BorderSide(color: PetsyColors.border)),
            boxShadow: PetsyShadows.soft,
          ),
          child: PetsyPressScale(
            onTap: busy ? null : onPlace,
            scale: 0.98,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: busy ? 0.72 : 1,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFD44318), PetsyColors.primary, PetsyColors.secondary],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: PetsyColors.primary.withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: busy
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                            )
                          : const Icon(Icons.verified_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.t('checkout_place_cta'),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            countLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        formatPrice(total),
                        style: const TextStyle(
                          color: PetsyColors.primaryDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckoutSteps extends StatelessWidget {
  const _CheckoutSteps({required this.current});

  final int current; // 0 cart, 1 shipping & payment, 2 confirmed

  @override
  Widget build(BuildContext context) {
    final steps = [
      (Icons.shopping_cart_outlined, 'cart'),
      (Icons.local_shipping_outlined, 'checkout_step_shipping'),
      (Icons.verified_outlined, 'checkout_step_confirm'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: PetsyColors.surface,
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        border: Border.all(color: PetsyColors.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: i <= current ? PetsyColors.primary : PetsyColors.border,
                  ),
                ),
              ),
            _CheckoutStepDot(
              icon: steps[i].$1,
              label: context.t(steps[i].$2),
              active: i <= current,
              current: i == current,
            ),
          ],
        ],
      ),
    );
  }
}

class _CheckoutStepDot extends StatelessWidget {
  const _CheckoutStepDot({
    required this.icon,
    required this.label,
    required this.active,
    required this.current,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: active ? PetsyColors.primary : PetsyColors.backgroundAlt,
            shape: BoxShape.circle,
            border: Border.all(
              color: current ? PetsyColors.primaryDark : (active ? PetsyColors.primary : PetsyColors.border),
              width: current ? 2.4 : 1.2,
            ),
            boxShadow: current
                ? [
                    BoxShadow(
                      color: PetsyColors.primary.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            active && !current ? Icons.check_rounded : icon,
            size: 18,
            color: active ? Colors.white : PetsyColors.textLight,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: current ? FontWeight.w900 : FontWeight.w600,
            color: active ? PetsyColors.primaryDark : PetsyColors.textLight,
          ),
        ),
      ],
    );
  }
}

class _CheckoutSummaryRow extends StatelessWidget {
  const _CheckoutSummaryRow({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(PetsyRadius.md),
          child: SizedBox(
            width: 54,
            height: 54,
            child: NetImage(item.image, icon: Icons.shopping_bag_outlined),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                '×${item.quantity} · ${formatPrice(item.price)}',
                style: PetsyType.meta.copyWith(fontWeight: FontWeight.w600, fontSize: 12.5),
              ),
            ],
          ),
        ),
        Text(
          formatPrice(item.price * item.quantity),
          style: const TextStyle(fontWeight: FontWeight.w900, color: PetsyColors.primaryDark),
        ),
      ],
    );
  }
}

class OrderSuccessScreen extends StatelessWidget {
  const OrderSuccessScreen({super.key, this.order});

  final Order? order;

  @override
  Widget build(BuildContext context) {
    final shortId = order == null
        ? '—'
        : order!.id.length > 8
            ? order!.id.substring(0, 8)
            : order!.id;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/shop');
      },
      child: PetsyPage(
      appBar: AppBar(
        title: Text(context.t('order_placed')),
        automaticallyImplyLeading: false,
      ),
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(
          PetsySpacing.page,
          PetsySpacing.md,
          PetsySpacing.page,
          PetsySpacing.listBottom,
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [PetsyColors.accentSoft, PetsyColors.mist, Color(0xFFFFF8F4)],
              ),
              borderRadius: BorderRadius.circular(PetsyRadius.xl),
              border: Border.all(color: PetsyColors.border),
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: PetsyColors.accent.withValues(alpha: 0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check_rounded, size: 36, color: PetsyColors.accent),
                ),
                const SizedBox(height: 16),
                Text(
                  context.t('order_success_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  context.t('order_success_body'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: PetsyColors.textSecondary, height: 1.4, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(PetsyRadius.lg),
                    border: Border.all(color: PetsyColors.border),
                  ),
                  child: Column(
                    children: [
                      Text(
                        context.t('order_success_number'),
                        style: const TextStyle(
                          color: PetsyColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '\u2066#$shortId\u2069',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: PetsyColors.primaryDark),
                      ),
                      if (order != null) ...[
                        const SizedBox(height: 8),
                        StatusChip(order!.status),
                        const SizedBox(height: 8),
                        Text(
                          formatPrice(order!.total),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: PetsyColors.primary),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PetsyColors.surface,
              borderRadius: BorderRadius.circular(PetsyRadius.xl),
              border: Border.all(color: PetsyColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.t('order_success_next'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 8),
                Text(
                  context.t('order_success_next_body'),
                  style: const TextStyle(color: PetsyColors.textSecondary, height: 1.4, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              context.go('/shop');
              context.push('/orders');
            },
            icon: const Icon(Icons.receipt_long_rounded),
            label: Text(context.t('order_view_orders')),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => context.go('/shop'),
            icon: const Icon(Icons.storefront_rounded),
            label: Text(context.t('order_continue_shop')),
          ),
        ],
      ),
      ),
    );
  }
}

Future<void> reorderPreviousOrder(BuildContext context, Order order) async {
  if (order.items.isEmpty) {
    context.snack(context.t('reorder_unavailable'), error: true);
    return;
  }

  final cart = context.read<CartState>();
  if (cart.count > 0) {
    final ok = await confirmAction(
      context,
      title: context.t('reorder_merge_title'),
      message: context.t('reorder_merge_body'),
      confirmLabel: context.t('reorder_merge_confirm'),
      color: PetsyColors.primary,
      icon: Icons.replay_rounded,
    );
    if (!ok || !context.mounted) return;
  }

  context.snack(context.t('reorder_busy'), icon: Icons.hourglass_top_rounded);

  var addedQty = 0;
  var skipped = 0;
  final toAdd = <CartItem>[];

  for (final item in order.items) {
    try {
      final product = await context.api.product(item.productId);
      if (!product.inStock) {
        skipped++;
        continue;
      }
      toAdd.add(CartItem(
        productId: product.id,
        name: product.name,
        price: product.price,
        image: product.image,
        quantity: item.quantity,
      ));
      addedQty += item.quantity;
    } catch (_) {
      // Product endpoint failed — keep the order snapshot so reorder still works.
      toAdd.add(CartItem(
        productId: item.productId,
        name: item.name,
        price: item.price,
        image: item.image,
        quantity: item.quantity,
      ));
      addedQty += item.quantity;
    }
  }

  if (!context.mounted) return;
  if (toAdd.isEmpty) {
    context.snack(context.t('reorder_unavailable'), error: true);
    return;
  }

  cart.addCartItems(toAdd);
  if (skipped > 0) {
    context.snack(
      context
          .t('reorder_partial')
          .replaceAll('{added}', '$addedQty')
          .replaceAll('{skipped}', '$skipped'),
      success: true,
      icon: Icons.shopping_cart_checkout_rounded,
    );
  } else {
    context.snack(
      context.t('reorder_success').replaceAll('{count}', '$addedQty'),
      success: true,
      icon: Icons.shopping_cart_checkout_rounded,
    );
  }
  context.push('/cart');
}

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String? _status; // null = all
  static const _statuses = ['pending', 'confirmed', 'shipped', 'delivered', 'cancelled'];

  Future<void> _showOrderDetails(BuildContext context, Order order) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _OrderDetailsSheet(
        order: order,
        onReorder: () async {
          Navigator.pop(ctx);
          await reorderPreviousOrder(context, order);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PetsyPage(
      appBar: AppBar(title: Text(context.t('orders'))),
      child: AsyncView<List<Order>>(
        loader: context.api.orders,
        builder: (context, orders, reload) {
          final visible = _status == null ? orders : orders.where((o) => o.status == _status).toList();
          final active = orders
              .where((o) => o.status == 'pending' || o.status == 'confirmed' || o.status == 'shipped')
              .length;
          final delivered = orders.where((o) => o.status == 'delivered').length;

          return RefreshIndicator(
            onRefresh: reload,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: _OrdersHero()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 14, PetsySpacing.page, 0),
                    child: _OrdersStatsRow(
                      total: orders.length,
                      active: active,
                      delivered: delivered,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
                    child: PetsyFilterRow(
                      children: [
                        for (var i = 0; i < _statuses.length + 1; i++)
                          PetsyPill(
                            label: context.t(i == 0 ? 'orders_filter_all' : _statuses[i - 1]),
                            selected: (i == 0 ? null : _statuses[i - 1]) == _status,
                            onTap: () => setState(() => _status = i == 0 ? null : _statuses[i - 1]),
                          ),
                      ],
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
                      child: _OrdersEmptyState(
                        filtered: orders.isNotEmpty,
                        onClearFilter: () => setState(() => _status = null),
                      ),
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
                      itemBuilder: (context, i) => _OrderCard(
                        order: visible[i],
                        onOpen: () => _showOrderDetails(context, visible[i]),
                        onReorder: () => reorderPreviousOrder(context, visible[i]),
                      ),
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

class _OrdersHero extends StatefulWidget {
  const _OrdersHero();

  @override
  State<_OrdersHero> createState() => _OrdersHeroState();
}

class _OrdersHeroState extends State<_OrdersHero> with SingleTickerProviderStateMixin {
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
                    Color(0xFFD44318),
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
                top: -12,
                child: Icon(Icons.receipt_long_rounded, size: 112, color: Colors.white.withValues(alpha: 0.12)),
              ),
              Positioned(
                left: -16,
                bottom: -22,
                child: Icon(Icons.local_shipping_rounded, size: 86, color: Colors.white.withValues(alpha: 0.08)),
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
                        context.t('orders_hero_tag'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.t('orders_hero_title'),
                      style: PetsyType.title.copyWith(color: Colors.white, fontSize: 22, height: 1.2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t('orders_subtitle'),
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

class _OrdersStatsRow extends StatelessWidget {
  const _OrdersStatsRow({
    required this.total,
    required this.active,
    required this.delivered,
  });

  final int total;
  final int active;
  final int delivered;

  @override
  Widget build(BuildContext context) {
    final totalLabel = total == 1
        ? context.t('orders_stat_total_one')
        : context.t('orders_stat_total').replaceAll('{count}', '$total');
    return Row(
      children: [
        Expanded(
          child: _OrdersStatTile(
            icon: Icons.inventory_2_outlined,
            label: totalLabel,
            color: PetsyColors.primaryDark,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _OrdersStatTile(
            icon: Icons.timelapse_rounded,
            label: context.t('orders_stat_active').replaceAll('{count}', '$active'),
            color: PetsyColors.warning,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _OrdersStatTile(
            icon: Icons.check_circle_outline_rounded,
            label: context.t('orders_stat_delivered').replaceAll('{count}', '$delivered'),
            color: PetsyColors.success,
          ),
        ),
      ],
    );
  }
}

class _OrdersStatTile extends StatelessWidget {
  const _OrdersStatTile({
    required this.icon,
    required this.label,
    required this.color,
  });

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

class _OrdersEmptyState extends StatelessWidget {
  const _OrdersEmptyState({required this.filtered, required this.onClearFilter});

  final bool filtered;
  final VoidCallback onClearFilter;

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
                color: PetsyColors.primarySoft,
                shape: BoxShape.circle,
                border: Border.all(color: PetsyColors.primary.withValues(alpha: 0.18)),
              ),
              child: Icon(
                filtered ? Icons.filter_alt_off_outlined : Icons.receipt_long_outlined,
                size: 36,
                color: PetsyColors.primaryDark,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              filtered ? context.t('notif_empty_filter') : context.t('orders_empty_title'),
              textAlign: TextAlign.center,
              style: PetsyType.section.copyWith(fontSize: 18),
            ),
            if (!filtered) ...[
              const SizedBox(height: 8),
              Text(
                context.t('orders_empty_body'),
                textAlign: TextAlign.center,
                style: PetsyType.meta.copyWith(height: 1.4, fontSize: 14),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: filtered
                  ? OutlinedButton(
                      onPressed: onClearFilter,
                      child: Text(context.t('orders_filter_all')),
                    )
                  : FilledButton.icon(
                      onPressed: () => context.go('/shop'),
                      icon: const Icon(Icons.storefront_rounded),
                      label: Text(context.t('cart_browse_shop')),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

int _orderProgressStep(String status) => switch (status) {
      'pending' => 0,
      'confirmed' => 1,
      'shipped' => 2,
      'delivered' => 3,
      'cancelled' => -1,
      _ => 0,
    };

class _OrderProgressBar extends StatelessWidget {
  const _OrderProgressBar({required this.status, this.compact = false});

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (status == 'cancelled') {
      return Row(
        children: [
          const Icon(Icons.cancel_outlined, size: 16, color: PetsyColors.error),
          const SizedBox(width: 6),
          Text(
            context.t('cancelled'),
            style: const TextStyle(color: PetsyColors.error, fontWeight: FontWeight.w800, fontSize: 12.5),
          ),
        ],
      );
    }

    final step = _orderProgressStep(status);
    final labels = ['pending', 'confirmed', 'shipped', 'delivered'];
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0)
                Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: i <= step ? PetsyColors.primary : PetsyColors.border,
                    ),
                  ),
                ),
              Container(
                width: compact ? 18 : 22,
                height: compact ? 18 : 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i <= step ? PetsyColors.primary : PetsyColors.backgroundAlt,
                  border: Border.all(
                    color: i <= step ? PetsyColors.primary : PetsyColors.border,
                    width: 1.4,
                  ),
                ),
                child: i <= step
                    ? Icon(Icons.check_rounded, size: compact ? 11 : 13, color: Colors.white)
                    : null,
              ),
            ],
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final key in labels)
                Text(
                  context.t(key),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: key == status ? FontWeight.w900 : FontWeight.w600,
                    color: key == status ? PetsyColors.primaryDark : PetsyColors.textLight,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.onOpen,
    required this.onReorder,
  });

  final Order order;
  final VoidCallback onOpen;
  final VoidCallback onReorder;

  @override
  Widget build(BuildContext context) {
    final shortId = order.id.length > 8 ? order.id.substring(0, 8) : order.id;
    final itemsLabel = order.items.length == 1
        ? context.t('order_items_count_one')
        : context.t('order_items_count').replaceAll('{count}', '${order.items.length}');
    final thumbs = order.items.take(3).toList();
    final canReorder = order.items.isNotEmpty && order.status != 'cancelled';

    return PetsyRaisedCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(14),
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${context.t('order')} \u2066#$shortId\u2069',
                  style: PetsyType.cardTitle.copyWith(fontSize: 15.5),
                ),
              ),
              StatusChip(order.status),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < thumbs.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: NetImage(thumbs[i].image, icon: Icons.shopping_bag_outlined),
                  ),
                ),
              ],
              if (order.items.length > 3) ...[
                const SizedBox(width: 6),
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: PetsyColors.mist,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: PetsyColors.border),
                  ),
                  child: Text(
                    '+${order.items.length - 3}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: PetsyColors.primaryDark),
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  order.items.map((e) => '${e.name} ×${e.quantity}').join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: PetsyType.meta.copyWith(height: 1.35, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _OrderProgressBar(status: order.status, compact: true),
          if (order.shippingCity.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 15, color: PetsyColors.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${context.t('order_ship_to')} ${order.shippingCity}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: PetsyColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: PetsyColors.border),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                itemsLabel,
                style: const TextStyle(fontSize: 12.5, color: PetsyColors.textLight, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Text(
                context.formatDate(order.createdAt),
                style: const TextStyle(fontSize: 12.5, color: PetsyColors.textLight, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                formatPrice(order.total),
                style: const TextStyle(fontWeight: FontWeight.w900, color: PetsyColors.primaryDark, fontSize: 16),
              ),
              const SizedBox(width: 4),
              const PetsyChevron.forward(),
            ],
          ),
          if (canReorder) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onReorder,
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: Text(context.t('reorder')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderDetailsSheet extends StatelessWidget {
  const _OrderDetailsSheet({required this.order, required this.onReorder});

  final Order order;
  final VoidCallback onReorder;

  @override
  Widget build(BuildContext context) {
    final shortId = order.id.length > 8 ? order.id.substring(0, 8) : order.id;
    final canReorder = order.items.isNotEmpty && order.status != 'cancelled';

    return Material(
      color: PetsyColors.backgroundAlt,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(PetsyRadius.xl)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.82),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(PetsySpacing.page, 10, PetsySpacing.page, PetsySpacing.page),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: PetsyColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(context.t('orders_details'), style: PetsyType.section),
                    ),
                    StatusChip(order.status),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    '${context.t('order')} #$shortId · ${context.formatDate(order.createdAt)}',
                    style: PetsyType.meta.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      SectionCard(
                        title: context.t('orders_status_progress'),
                        child: _OrderProgressBar(status: order.status),
                      ),
                      const SizedBox(height: 12),
                      SectionCard(
                        title: context.t('orders_items_section'),
                        child: Column(
                          children: [
                            for (var i = 0; i < order.items.length; i++) ...[
                              if (i > 0) const Divider(height: 18, color: PetsyColors.border),
                              _CheckoutSummaryRow(item: order.items[i]),
                            ],
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: PetsyColors.mist,
                                borderRadius: BorderRadius.circular(PetsyRadius.md),
                              ),
                              child: Row(
                                children: [
                                  Text(context.t('total'), style: const TextStyle(fontWeight: FontWeight.w800)),
                                  const Spacer(),
                                  Text(
                                    formatPrice(order.total),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 17,
                                      color: PetsyColors.primaryDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (order.shippingCity.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SectionCard(
                          title: context.t('checkout_shipping_section'),
                          child: Row(
                            children: [
                              const Icon(Icons.place_outlined, color: PetsyColors.primaryDark),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${context.t('order_ship_to')} ${order.shippingCity}',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (canReorder) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: onReorder,
                      icon: const Icon(Icons.replay_rounded),
                      label: Text(context.t('reorder')),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: order.id));
                          if (context.mounted) {
                            context.snack(
                              context.t('orders_id_copied'),
                              success: true,
                              icon: Icons.copy_rounded,
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_rounded),
                        label: Text(context.t('orders_copy_id')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          context.go('/shop');
                        },
                        icon: const Icon(Icons.storefront_rounded),
                        label: Text(context.t('orders_shop_again')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
