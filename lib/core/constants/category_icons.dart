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
  'laptop': Icons.laptop_mac_rounded,
  'card_giftcard': Icons.card_giftcard_rounded,
  'savings': Icons.savings_rounded,
  'swap_horiz': Icons.swap_horiz_rounded,
};

IconData iconFor(String name) => kCategoryIcons[name] ?? Icons.category_rounded;

/// The colour to draw a category in.
///
/// Categories store the colour they were created with. The first set of
/// default colours was muted (brown rent, grey-brown bills); those exact
/// values are shown as the brighter defaults new accounts now get, so
/// existing users see the same palette without their data being rewritten.
/// A colour the user picked themselves is shown as it is.
Color categoryColor(int stored) => Color(_refreshedDefaults[stored] ?? stored);

const _refreshedDefaults = <int, int>{
  0xFFEF6C00: 0xFFF97316, // Food: orange
  0xFF1E88E5: 0xFF3B82F6, // Transport: blue
  0xFFD81B60: 0xFFEC4899, // Shopping: pink
  0xFF6D4C41: 0xFFF59E0B, // Bills: amber
  0xFF5D4037: 0xFF7C5CFC, // Rent: violet
  0xFF8E24AA: 0xFF06B6D4, // Entertainment: cyan
  0xFFE53935: 0xFFEF4444, // Health: red
  0xFF3949AB: 0xFF6366F1, // Education: indigo
  0xFF757575: 0xFF64748B, // Other: slate
  0xFF2E7D32: 0xFF22C55E, // Salary: green
  0xFF00897B: 0xFF14B8A6, // Business: teal
  0xFF0288D1: 0xFF0EA5E9, // Freelance: sky
  0xFFC2185B: 0xFFF472B6, // Gift: rose
  0xFF43A047: 0xFFEAB308, // Investment: gold
};
