import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'credits.dart';
import 'theme.dart';

/// Opens a WhatsApp chat with the designer. Falls back to the WhatsApp web
/// link when the app is not installed, and reports if nothing can handle it.
Future<void> openWhatsApp(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final uri = Designer.whatsappUri;
  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched) return;
  } catch (_) {
    // Fall through to the message below.
  }
  messenger?.showSnackBar(
    const SnackBar(
      content: Text('Could not open WhatsApp. The number is 07038193753.'),
    ),
  );
}

/// A tappable line that opens WhatsApp when tapped. Used wherever the designer
/// credit appears, so the number always routes to a chat.
class WhatsAppTile extends StatelessWidget {
  final String label;
  final bool compact;

  const WhatsAppTile({
    super.key,
    this.label = 'Chat on WhatsApp',
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    // WhatsApp brand green, kept constant regardless of the app accent.
    const whatsapp = Color(0xFF25D366);
    return InkWell(
      onTap: () => openWhatsApp(context),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 8 : 12,
        ),
        decoration: BoxDecoration(
          color: whatsapp.withOpacity(0.10),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: whatsapp.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.chat_rounded, color: whatsapp, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: TurboFonts.body,
                      color: TurboColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    Designer.phoneDisplay,
                    style: TextStyle(
                      fontFamily: TurboFonts.mono,
                      color: TurboColors.textSecondary,
                      fontSize: 11,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.open_in_new_rounded,
                color: TurboColors.textMuted, size: 15),
          ],
        ),
      ),
    );
  }
}
