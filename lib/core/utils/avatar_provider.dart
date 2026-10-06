import 'dart:convert';

import 'package:flutter/material.dart';

/// Decodes a `data:image/...;base64,...` URI, which is how a photo the user
/// picked themselves is stored in Firestore. Returns null for anything else
/// (including a remote URL) or for bytes that don't decode.
ImageProvider? dataUriImage(String? photoUrl) {
  if (photoUrl == null || !photoUrl.startsWith('data:image')) return null;
  try {
    return MemoryImage(base64Decode(photoUrl.split(',').last));
  } catch (_) {
    return null;
  }
}

/// True when [photoUrl] is a remote address we have to fetch and cache.
bool isRemoteAvatar(String? photoUrl) {
  final url = photoUrl?.trim();
  if (url == null || url.isEmpty) return false;
  return url.startsWith('http://') || url.startsWith('https://');
}

/// Up to two letters standing in for a missing photo.
///
/// Takes the first letter of the first and last words, so "A R Prathap" reads
/// as "AP". Falls back to the local part of [email] when there is no name —
/// an offline cold start can reach the dashboard before the profile document
/// loads, and a blank circle there looks like a bug.
String initialsFor(String? name, {String? email}) {
  final fromName = _initialsFrom(name);
  if (fromName.isNotEmpty) return fromName;
  final fromEmail = _initialsFrom(email);
  if (fromEmail.isNotEmpty) return fromEmail;
  return '?';
}

final _letter = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _wordBreak = RegExp(r'[\s._\-+]+');

String _initialsFrom(String? raw) {
  var value = raw?.trim() ?? '';
  if (value.isEmpty) return '';
  // An address in the name slot is an address, not a name.
  if (value.contains('@')) value = value.split('@').first;

  final letters = value
      .split(_wordBreak)
      .map((word) => _letter.firstMatch(word)?.group(0))
      .whereType<String>()
      .toList();

  if (letters.isEmpty) return '';
  if (letters.length == 1) return letters.first.toUpperCase();
  return '${letters.first}${letters.last}'.toUpperCase();
}
