import 'package:flutter/widgets.dart';

/// ISO country + dialing metadata for [PetsyPhoneField].
///
/// [nsnLength] is the national number length **without** the trunk prefix `0`,
/// because the dial code is already shown (e.g. Syria local `0957…` → type `957…`).
class PhoneCountry {
  const PhoneCountry({
    required this.iso,
    required this.dialCode,
    required this.nameEn,
    required this.nameAr,
    required this.flag,
    required this.nsnLength,
    required this.example,
  });

  final String iso;
  final String dialCode;
  final String nameEn;
  final String nameAr;
  final String flag;

  /// Digits the user must type after the dial code (no leading 0).
  final int nsnLength;

  /// Typical leading digit(s) used only to build a mask like `9xxxxxxxx` — not a real number.
  final String example;

  String get dialLabel => '+$dialCode';

  /// Placeholder pattern, e.g. Syria → `9xxxxxxxx` (no real digits beyond the prefix).
  String get mask {
    if (example.isEmpty) return 'x' * nsnLength;
    final lead = example[0];
    if (nsnLength <= 1) return lead;
    return '$lead${'x' * (nsnLength - 1)}';
  }

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final dial = dialCode.replaceAll('+', '');
    return nameEn.toLowerCase().contains(q) ||
        nameAr.contains(query.trim()) ||
        iso.toLowerCase().contains(q) ||
        dial.contains(q.replaceAll('+', '')) ||
        dialLabel.contains(q);
  }

  /// Normalize pasted/typed national input: digits only, strip trunk 0 / dial code.
  String normalizeNational(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (digits.startsWith(dialCode) && digits.length > dialCode.length + 3) {
      digits = digits.substring(dialCode.length);
      if (digits.startsWith('0')) digits = digits.substring(1);
    }
    if (digits.length > nsnLength) digits = digits.substring(0, nsnLength);
    return digits;
  }

  bool isValidNational(String raw) {
    final digits = normalizeNational(raw);
    return digits.length == nsnLength;
  }
}

PhoneCountry _c(
  String iso,
  String dial,
  String en,
  String ar,
  String flag,
  int len,
  String example,
) =>
    PhoneCountry(
      iso: iso,
      dialCode: dial,
      nameEn: en,
      nameAr: ar,
      flag: flag,
      nsnLength: len,
      example: example,
    );

final kPhoneCountries = <PhoneCountry>[
  // Syria: local mobiles are 10 digits with trunk 0 (09xxxxxxxx) → type 9 without 0.
  _c('SY', '963', 'Syria', 'سوريا', '🇸🇾', 9, '957261491'),
  _c('TR', '90', 'Turkey', 'تركيا', '🇹🇷', 10, '5321234567'),
  _c('LB', '961', 'Lebanon', 'لبنان', '🇱🇧', 8, '71123456'),
  _c('JO', '962', 'Jordan', 'الأردن', '🇯🇴', 9, '791234567'),
  _c('IQ', '964', 'Iraq', 'العراق', '🇮🇶', 10, '7701234567'),
  _c('SA', '966', 'Saudi Arabia', 'السعودية', '🇸🇦', 9, '512345678'),
  _c('AE', '971', 'United Arab Emirates', 'الإمارات', '🇦🇪', 9, '501234567'),
  _c('KW', '965', 'Kuwait', 'الكويت', '🇰🇼', 8, '50123456'),
  _c('QA', '974', 'Qatar', 'قطر', '🇶🇦', 8, '33123456'),
  _c('BH', '973', 'Bahrain', 'البحرين', '🇧🇭', 8, '36123456'),
  _c('OM', '968', 'Oman', 'عُمان', '🇴🇲', 8, '92123456'),
  _c('EG', '20', 'Egypt', 'مصر', '🇪🇬', 10, '1001234567'),
  _c('PS', '970', 'Palestine', 'فلسطين', '🇵🇸', 9, '591234567'),
  _c('YE', '967', 'Yemen', 'اليمن', '🇾🇪', 9, '712345678'),
  _c('DE', '49', 'Germany', 'ألمانيا', '🇩🇪', 11, '15123456789'),
  _c('SE', '46', 'Sweden', 'السويد', '🇸🇪', 9, '701234567'),
  _c('NL', '31', 'Netherlands', 'هولندا', '🇳🇱', 9, '612345678'),
  _c('FR', '33', 'France', 'فرنسا', '🇫🇷', 9, '612345678'),
  _c('GB', '44', 'United Kingdom', 'المملكة المتحدة', '🇬🇧', 10, '7400123456'),
  _c('US', '1', 'United States', 'الولايات المتحدة', '🇺🇸', 10, '2015550123'),
  _c('CA', '1', 'Canada', 'كندا', '🇨🇦', 10, '4165550123'),
  _c('AU', '61', 'Australia', 'أستراليا', '🇦🇺', 9, '412345678'),
  _c('RU', '7', 'Russia', 'روسيا', '🇷🇺', 10, '9123456789'),
  _c('UA', '380', 'Ukraine', 'أوكرانيا', '🇺🇦', 9, '501234567'),
  _c('IT', '39', 'Italy', 'إيطاليا', '🇮🇹', 10, '3123456789'),
  _c('ES', '34', 'Spain', 'إسبانيا', '🇪🇸', 9, '612345678'),
  _c('MA', '212', 'Morocco', 'المغرب', '🇲🇦', 9, '612345678'),
  _c('DZ', '213', 'Algeria', 'الجزائر', '🇩🇿', 9, '551234567'),
  _c('TN', '216', 'Tunisia', 'تونس', '🇹🇳', 8, '20123456'),
  _c('LY', '218', 'Libya', 'ليبيا', '🇱🇾', 9, '912345678'),
  _c('SD', '249', 'Sudan', 'السودان', '🇸🇩', 9, '912345678'),
  _c('IN', '91', 'India', 'الهند', '🇮🇳', 10, '9876543210'),
  _c('PK', '92', 'Pakistan', 'باكستان', '🇵🇰', 10, '3012345678'),
  _c('BD', '880', 'Bangladesh', 'بنغلاديش', '🇧🇩', 10, '1712345678'),
  _c('CN', '86', 'China', 'الصين', '🇨🇳', 11, '13123456789'),
  _c('JP', '81', 'Japan', 'اليابان', '🇯🇵', 10, '9012345678'),
  _c('KR', '82', 'South Korea', 'كوريا الجنوبية', '🇰🇷', 10, '1012345678'),
  _c('BR', '55', 'Brazil', 'البرازيل', '🇧🇷', 11, '11987654321'),
  _c('MX', '52', 'Mexico', 'المكسيك', '🇲🇽', 10, '5512345678'),
  _c('AR', '54', 'Argentina', 'الأرجنتين', '🇦🇷', 10, '9112345678'),
  _c('ZA', '27', 'South Africa', 'جنوب أفريقيا', '🇿🇦', 9, '821234567'),
  _c('NG', '234', 'Nigeria', 'نيجيريا', '🇳🇬', 10, '8012345678'),
  _c('KE', '254', 'Kenya', 'كينيا', '🇰🇪', 9, '712345678'),
  _c('MY', '60', 'Malaysia', 'ماليزيا', '🇲🇾', 9, '123456789'),
  _c('ID', '62', 'Indonesia', 'إندونيسيا', '🇮🇩', 11, '81234567890'),
  _c('PH', '63', 'Philippines', 'الفلبين', '🇵🇭', 10, '9171234567'),
  _c('SG', '65', 'Singapore', 'سنغافورة', '🇸🇬', 8, '81234567'),
  _c('TH', '66', 'Thailand', 'تايلاند', '🇹🇭', 9, '812345678'),
  _c('VN', '84', 'Vietnam', 'فيتنام', '🇻🇳', 9, '912345678'),
  _c('PL', '48', 'Poland', 'بولندا', '🇵🇱', 9, '512345678'),
  _c('RO', '40', 'Romania', 'رومانيا', '🇷🇴', 9, '712345678'),
  _c('GR', '30', 'Greece', 'اليونان', '🇬🇷', 10, '6912345678'),
  _c('AT', '43', 'Austria', 'النمسا', '🇦🇹', 10, '6641234567'),
  _c('CH', '41', 'Switzerland', 'سويسرا', '🇨🇭', 9, '781234567'),
  _c('BE', '32', 'Belgium', 'بلجيكا', '🇧🇪', 9, '470123456'),
  _c('DK', '45', 'Denmark', 'الدنمارك', '🇩🇰', 8, '20123456'),
  _c('NO', '47', 'Norway', 'النرويج', '🇳🇴', 8, '40612345'),
  _c('FI', '358', 'Finland', 'فنلندا', '🇫🇮', 9, '401234567'),
  _c('IE', '353', 'Ireland', 'أيرلندا', '🇮🇪', 9, '851234567'),
  _c('PT', '351', 'Portugal', 'البرتغال', '🇵🇹', 9, '912345678'),
  _c('CZ', '420', 'Czechia', 'التشيك', '🇨🇿', 9, '601123456'),
  _c('HU', '36', 'Hungary', 'المجر', '🇭🇺', 9, '201234567'),
  _c('NZ', '64', 'New Zealand', 'نيوزيلندا', '🇳🇿', 9, '211234567'),
];

PhoneCountry? phoneCountryByIso(String iso) {
  final code = iso.toUpperCase();
  for (final c in kPhoneCountries) {
    if (c.iso == code) return c;
  }
  return null;
}

/// Detect ISO from device region/locale. Petsy defaults to Syria.
PhoneCountry detectPhoneCountry() {
  final locale = WidgetsBinding.instance.platformDispatcher.locale;
  final country = locale.countryCode?.toUpperCase();
  final byIso = country == null ? null : phoneCountryByIso(country);
  if (byIso != null) return byIso;

  switch (locale.languageCode) {
    case 'ar':
      return phoneCountryByIso('SY')!;
    case 'tr':
      return phoneCountryByIso('TR')!;
    case 'de':
      return phoneCountryByIso('DE')!;
    case 'fr':
      return phoneCountryByIso('FR')!;
    case 'en':
      return phoneCountryByIso('GB')!;
    default:
      return phoneCountryByIso('SY')!;
  }
}

class ParsedPhone {
  const ParsedPhone({required this.country, required this.national});
  final PhoneCountry country;
  final String national;
}

/// Split a stored `+9639…` (or bare digits) into country + national number.
ParsedPhone parseStoredPhone(String? raw) {
  final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return ParsedPhone(country: detectPhoneCountry(), national: '');

  final sorted = [...kPhoneCountries]..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));
  for (final c in sorted) {
    if (digits.startsWith(c.dialCode) && digits.length >= c.dialCode.length + c.nsnLength - 1) {
      return ParsedPhone(country: c, national: c.normalizeNational(digits.substring(c.dialCode.length)));
    }
  }
  final fallback = detectPhoneCountry();
  return ParsedPhone(country: fallback, national: fallback.normalizeNational(digits));
}
