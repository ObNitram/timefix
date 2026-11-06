import 'package:timezone/timezone.dart' as tz;

/// Device time zone, falling back to UTC if the database is not initialized.
tz.Location get deviceLocation {
  try {
    return tz.local;
  } catch (_) {
    return tz.UTC;
  }
}

/// IANA name of the device time zone, if known.
String? get deviceTimeZoneName {
  try {
    final name = tz.local.name;
    return name == 'UTC' ? null : name;
  } catch (_) {
    return null;
  }
}
