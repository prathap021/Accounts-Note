import 'dart:convert';
import 'package:flutter/material.dart';

ImageProvider? getAvatarProvider(String? photoUrl) {
  if (photoUrl == null || photoUrl.isEmpty) return null;
  if (photoUrl.startsWith('data:image')) {
    final base64String = photoUrl.split(',').last;
    try {
      return MemoryImage(base64Decode(base64String));
    } catch (e) {
      return null;
    }
  }
  return NetworkImage(photoUrl);
}
