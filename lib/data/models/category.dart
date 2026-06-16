import 'package:flutter/material.dart';

/// A spending category — either one of the predefined set or a dynamic
/// label invented by the AI for items that don't fit the defaults.
class Category {
  final String key;
  final String label;
  final IconData icon;
  final Color color;

  const Category({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  bool operator ==(Object other) =>
      other is Category && other.key.toLowerCase() == key.toLowerCase();

  @override
  int get hashCode => key.toLowerCase().hashCode;

  @override
  String toString() => 'Category($key)';

  // ── Predefined categories ──────────────────────────────────────────────────
  static const groceries = Category(
    key: 'groceries', label: 'Groceries',
    icon: Icons.local_grocery_store_outlined, color: Color(0xFF22C55E),
  );
  static const fuel = Category(
    key: 'fuel', label: 'Fuel',
    icon: Icons.local_gas_station_outlined, color: Color(0xFFF97316),
  );
  static const rent = Category(
    key: 'rent', label: 'Rent',
    icon: Icons.home_outlined, color: Color(0xFF8B5CF6),
  );
  static const utilities = Category(
    key: 'utilities', label: 'Utilities',
    icon: Icons.bolt_outlined, color: Color(0xFFEAB308),
  );
  static const transport = Category(
    key: 'transport', label: 'Transport',
    icon: Icons.directions_bus_outlined, color: Color(0xFF3B82F6),
  );
  static const entertainment = Category(
    key: 'entertainment', label: 'Entertainment',
    icon: Icons.movie_outlined, color: Color(0xFFEC4899),
  );
  static const businessSupplies = Category(
    key: 'businesssupplies', label: 'Business Supplies',
    icon: Icons.inventory_2_outlined, color: Color(0xFF14B8A6),
  );
  static const staffExpenses = Category(
    key: 'staffexpenses', label: 'Staff Expenses',
    icon: Icons.groups_outlined, color: Color(0xFF6366F1),
  );
  static const school = Category(
    key: 'school', label: 'School',
    icon: Icons.school_outlined, color: Color(0xFF0EA5E9),
  );
  static const medical = Category(
    key: 'medical', label: 'Medical',
    icon: Icons.medical_services_outlined, color: Color(0xFFEF4444),
  );
  static const other = Category(
    key: 'other', label: 'Other',
    icon: Icons.receipt_long_outlined, color: Color(0xFF64748B),
  );

  /// All predefined categories — use instead of the old enum `.values`.
  static const predefined = [
    groceries, fuel, rent, utilities, transport,
    entertainment, businessSupplies, staffExpenses, school, medical, other,
  ];

  // ── Palette for AI-invented categories ────────────────────────────────────
  static const _paletteIcons = [
    Icons.sell_outlined,
    Icons.star_outline,
    Icons.shopping_bag_outlined,
    Icons.local_offer_outlined,
    Icons.workspace_premium_outlined,
    Icons.emoji_objects_outlined,
    Icons.card_giftcard_outlined,
    Icons.sports_outlined,
    Icons.pets_outlined,
    Icons.tag_outlined,
  ];

  static const _paletteColors = [
    Color(0xFF6366F1),
    Color(0xFF14B8A6),
    Color(0xFFF97316),
    Color(0xFFEC4899),
    Color(0xFF06B6D4),
    Color(0xFF84CC16),
    Color(0xFFF43F5E),
    Color(0xFF8B5CF6),
    Color(0xFFF59E0B),
    Color(0xFF0EA5E9),
  ];

  // ── Factory ───────────────────────────────────────────────────────────────
  /// Returns a predefined match or auto-generates one with a deterministic
  /// icon + color from the palette (so the same label always looks the same).
  static Category fromKey(String? raw) {
    if (raw == null || raw.trim().isEmpty) return other;
    final normalised = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    final match = predefined.cast<Category?>().firstWhere(
      (c) =>
          c!.key.replaceAll(RegExp(r'[\s_-]+'), '') == normalised ||
          c.label.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '') == normalised,
      orElse: () => null,
    );
    return match ?? _dynamic(raw.trim());
  }

  static Category _dynamic(String label) {
    final idx = label.hashCode.abs() % _paletteIcons.length;
    return Category(
      key: label.toLowerCase().replaceAll(RegExp(r'[\s]+'), '_'),
      label: label,
      icon: _paletteIcons[idx],
      color: _paletteColors[idx],
    );
  }
}

/// Backwards-compatibility aliases so existing code compiles unchanged.
typedef ExpenseCategory = Category;
typedef ExpenseCategoryX = Category;
