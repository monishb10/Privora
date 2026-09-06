import 'package:flutter/material.dart';

/// User-created category model.
/// Strict rule: No default categories. Every category is created manually by the user.
class VaultCategory {
  final String id;
  final String userId;
  final String name;
  final int colorValue;
  final String? coverPhotoId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int photoCount;
  final DateTime? latestPhotoDate;

  const VaultCategory({
    required this.id,
    required this.userId,
    required this.name,
    required this.colorValue,
    this.coverPhotoId,
    required this.createdAt,
    required this.updatedAt,
    this.photoCount = 0,
    this.latestPhotoDate,
  });

  Color get color => Color(colorValue);

  factory VaultCategory.fromJson(
    Map<String, dynamic> json, {
    int photoCount = 0,
    DateTime? latestPhotoDate,
  }) {
    return VaultCategory(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      colorValue: (json['color_value'] is int)
          ? json['color_value'] as int
          : int.parse(json['color_value'].toString()),
      coverPhotoId: json['cover_photo_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      photoCount: photoCount,
      latestPhotoDate: latestPhotoDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'user_id': userId,
      'name': name,
      'color_value': colorValue,
      'cover_photo_id': coverPhotoId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertMap({String? userId}) {
    return {
      if (id.isNotEmpty) 'id': id,
      'user_id': userId ?? this.userId,
      'name': name,
      'color_value': colorValue,
      if (coverPhotoId != null && coverPhotoId!.isNotEmpty)
        'cover_photo_id': coverPhotoId,
    };
  }

  VaultCategory copyWith({
    String? id,
    String? userId,
    String? name,
    int? colorValue,
    String? coverPhotoId,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? photoCount,
    DateTime? latestPhotoDate,
  }) {
    return VaultCategory(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      coverPhotoId: coverPhotoId ?? this.coverPhotoId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      photoCount: photoCount ?? this.photoCount,
      latestPhotoDate: latestPhotoDate ?? this.latestPhotoDate,
    );
  }
}
