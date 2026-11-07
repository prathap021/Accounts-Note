import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Where the user is, as a country code ("IN", "DE"), from the phone's
/// approximate location.
///
/// Used once, when the app is first set up, to choose the currency. The
/// position is turned into a country on the device and then dropped: it is
/// never stored or sent anywhere.
abstract class CountryLocator {
  /// Null when location is off, not allowed, or cannot be placed.
  Future<String?> countryFromLocation();
}

class DeviceCountryLocator implements CountryLocator {
  const DeviceCountryLocator();

  static const _timeout = Duration(seconds: 12);

  @override
  Future<String?> countryFromLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        return null;
      }

      // A recent fix is enough to know the country, and instant.
      final position =
          await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: _timeout,
            ),
          );
      final places = await Geocoding()
          .placemarkFromCoordinates(position.latitude, position.longitude)
          .timeout(_timeout);
      for (final place in places) {
        final code = place.isoCountryCode;
        if (code != null && code.isNotEmpty) return code.toUpperCase();
      }
      return null;
    } catch (e) {
      // No fix, no geocoder (some devices without Google services), no
      // network for the lookup: fall back to the phone's region.
      debugPrint('Country from location unavailable: $e');
      return null;
    }
  }
}

final countryLocatorProvider = Provider<CountryLocator>((ref) {
  return const DeviceCountryLocator();
});
