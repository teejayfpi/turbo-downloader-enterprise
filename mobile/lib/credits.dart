/// Product identity, kept in sync with the web client's `credits.js`.
class Designer {
  static const name = 'Ayanlowo Olatunji Ayobami';
  static const email = 'ayanlowo89@gmail.com';
  static const phone = '+2347038193753';
  static const phoneHref = '+2347038193753';

  /// The phone number as shown to the user.
  static const phoneDisplay = '07038193753';

  /// International form (digits only) used to open a WhatsApp chat.
  static const whatsappNumber = '2347038193753';

  /// Opens a WhatsApp chat with the designer, falling back to the app's
  /// web link when WhatsApp is not installed.
  static Uri get whatsappUri =>
      Uri.parse('https://wa.me/$whatsappNumber');
}

/// The version shown in the splash, Settings, and the update check. Keep in
/// sync with `version:` in pubspec.yaml — `test/version_test.dart` enforces it.
const appVersion = '2.4.0';
