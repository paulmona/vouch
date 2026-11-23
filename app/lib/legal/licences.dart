import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Shown under About > Open-source licences: Vouch's own licence and
/// notice (copies of the repository's, kept equal by a test) and the
/// bundled fonts' OFL texts.
void registerLicences() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Vouch',
    ], await rootBundle.loadString('assets/legal/NOTICE'));
    yield LicenseEntryWithLineBreaks(const [
      'Vouch',
    ], await rootBundle.loadString('assets/legal/LICENSE'));
    yield LicenseEntryWithLineBreaks(const [
      'Inter',
    ], await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'Instrument Serif',
    ], await rootBundle.loadString('assets/fonts/InstrumentSerif-OFL.txt'));
  });
}
