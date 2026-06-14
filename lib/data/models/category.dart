import 'package:flutter/material.dart';

/// Expense categories used for AI auto-categorization.
enum ExpenseCategory {
  groceries,
  fuel,
  rent,
  utilities,
  transport,
  entertainment,
  businessSupplies,
  staffExpenses,
  school,
  medical,
  other,
}

extension ExpenseCategoryX on ExpenseCategory {
  String get label {
    switch (this) {
      case ExpenseCategory.groceries:
        return 'Groceries';
      case ExpenseCategory.fuel:
        return 'Fuel';
      case ExpenseCategory.rent:
        return 'Rent';
      case ExpenseCategory.utilities:
        return 'Utilities';
      case ExpenseCategory.transport:
        return 'Transport';
      case ExpenseCategory.entertainment:
        return 'Entertainment';
      case ExpenseCategory.businessSupplies:
        return 'Business Supplies';
      case ExpenseCategory.staffExpenses:
        return 'Staff Expenses';
      case ExpenseCategory.school:
        return 'School';
      case ExpenseCategory.medical:
        return 'Medical';
      case ExpenseCategory.other:
        return 'Other';
    }
  }

  /// Stable key used in storage and for the AI to return.
  String get key => name;

  IconData get icon {
    switch (this) {
      case ExpenseCategory.groceries:
        return Icons.local_grocery_store_outlined;
      case ExpenseCategory.fuel:
        return Icons.local_gas_station_outlined;
      case ExpenseCategory.rent:
        return Icons.home_outlined;
      case ExpenseCategory.utilities:
        return Icons.bolt_outlined;
      case ExpenseCategory.transport:
        return Icons.directions_bus_outlined;
      case ExpenseCategory.entertainment:
        return Icons.movie_outlined;
      case ExpenseCategory.businessSupplies:
        return Icons.inventory_2_outlined;
      case ExpenseCategory.staffExpenses:
        return Icons.groups_outlined;
      case ExpenseCategory.school:
        return Icons.school_outlined;
      case ExpenseCategory.medical:
        return Icons.medical_services_outlined;
      case ExpenseCategory.other:
        return Icons.receipt_long_outlined;
    }
  }

  Color get color {
    switch (this) {
      case ExpenseCategory.groceries:
        return const Color(0xFF22C55E);
      case ExpenseCategory.fuel:
        return const Color(0xFFF97316);
      case ExpenseCategory.rent:
        return const Color(0xFF8B5CF6);
      case ExpenseCategory.utilities:
        return const Color(0xFFEAB308);
      case ExpenseCategory.transport:
        return const Color(0xFF3B82F6);
      case ExpenseCategory.entertainment:
        return const Color(0xFFEC4899);
      case ExpenseCategory.businessSupplies:
        return const Color(0xFF14B8A6);
      case ExpenseCategory.staffExpenses:
        return const Color(0xFF6366F1);
      case ExpenseCategory.school:
        return const Color(0xFF0EA5E9);
      case ExpenseCategory.medical:
        return const Color(0xFFEF4444);
      case ExpenseCategory.other:
        return const Color(0xFF64748B);
    }
  }

  static ExpenseCategory fromKey(String? key) {
    if (key == null) return ExpenseCategory.other;
    return ExpenseCategory.values.firstWhere(
      (c) => c.name.toLowerCase() == key.toLowerCase(),
      orElse: () => ExpenseCategory.other,
    );
  }
}
