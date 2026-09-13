import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import '../core/constants/app_constants.dart';

class CategoryModel extends Equatable {
  final String id;
  final String name;
  final String icon; // Material icon name, mapped in UI layer
  final int color; // ARGB int
  final TransactionType type;
  final bool isDefault; // default categories can't be deleted, only hidden
  final bool isArchived;
  final DateTime createdAt;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.type,
    this.isDefault = false,
    this.isArchived = false,
    required this.createdAt,
  });

  CategoryModel copyWith({
    String? name,
    String? icon,
    int? color,
    bool? isArchived,
  }) {
    return CategoryModel(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      type: type,
      isDefault: isDefault,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'icon': icon,
        'color': color,
        'type': type.name,
        'isDefault': isDefault,
        'isArchived': isArchived,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory CategoryModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return CategoryModel(
      id: doc.id,
      name: data['name'] as String,
      icon: data['icon'] as String? ?? 'category',
      color: data['color'] as int? ?? 0xFF757575,
      type: TransactionType.values.firstWhere(
        (t) => t.name == data['type'],
        orElse: () => TransactionType.expense,
      ),
      isDefault: data['isDefault'] as bool? ?? false,
      isArchived: data['isArchived'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, name, icon, color, type, isDefault, isArchived];
}
