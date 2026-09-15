import 'package:flutter/material.dart';

/// Small curated icon set users can assign to categories. Shared by the
/// category editor and every picker that renders a category, so an icon
/// always looks the same wherever it appears.
const kCategoryIcons = <String, IconData>{
  'category': Icons.category_rounded,
  'restaurant': Icons.restaurant_rounded,
  'directions_car': Icons.directions_car_rounded,
  'shopping_bag': Icons.shopping_bag_rounded,
  'receipt_long': Icons.receipt_long_rounded,
  'movie': Icons.movie_rounded,
  'local_hospital': Icons.local_hospital_rounded,
  'school': Icons.school_rounded,
  'work': Icons.work_rounded,
  'store': Icons.store_rounded,
  'trending_up': Icons.trending_up_rounded,
  'flight': Icons.flight_rounded,
  'pets': Icons.pets_rounded,
  'sports_esports': Icons.sports_esports_rounded,
  'home': Icons.home_rounded,
};

IconData iconFor(String name) => kCategoryIcons[name] ?? Icons.category_rounded;
