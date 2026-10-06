import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';

/// Sentinel returned when the user chooses "Start now". A real start time is
/// always in the future, so an epoch timestamp can never collide with one.
final DateTime startNowSentinel = DateTime.fromMillisecondsSinceEpoch(0);

/// Shows the start-time picker. Returns the chosen time, [startNowSentinel]
/// when the user picked "Start now", or null when the sheet was dismissed.
Future<DateTime?> showScheduleSheet(
  BuildContext context, {
  DateTime? initial,
}) {
  return showModalBottomSheet<DateTime?>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ScheduleSheet(initial: initial),
  );
}

/// Bottom sheet for choosing a start time: quick presets plus a date/time
/// picker for anything else.
class _ScheduleSheet extends StatelessWidget {
  final DateTime? initial;
  const _ScheduleSheet({this.initial});

  Future<void> _pickCustom(BuildContext context) async {
    final now = DateTime.now();
    final base = initial ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null || !context.mounted) return;
    Navigator.of(context).pop(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final now = DateTime.now();
    final soon = now.add(const Duration(minutes: 15));
    final tonight = DateTime(now.year, now.month, now.day, 22, 0);
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 8, 0);

    Widget preset(String label, String detail, IconData icon, DateTime? at) {
      return ListTile(
        leading: Icon(icon, color: p.textSecondary),
        title: Text(label,
            style: TextStyle(
                fontFamily: TurboFonts.body,
                color: p.textPrimary,
                fontSize: 13.5)),
        subtitle: detail.isEmpty
            ? null
            : Text(detail,
                style: TextStyle(
                    fontFamily: TurboFonts.mono,
                    color: p.textMuted,
                    fontSize: 10.5)),
        onTap: () {
          if (at == null) {
            _pickCustom(context);
          } else {
            Navigator.of(context).pop(at);
          }
        },
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: p.borderSubtle,
                  borderRadius: TurboRadius.all(TurboRadius.pill),
                ),
              ),
            ),
            const Kicker('Schedule this download', letterSpacing: 2.0),
            const SizedBox(height: 6),
            Text(
              'The link is queued now and the transfer starts on its own — the '
              'app does not need to stay open.',
              style: TextStyle(
                fontFamily: TurboFonts.body,
                color: p.textMuted,
                fontSize: 11,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 10),
            preset('Start now', '', Icons.play_arrow_rounded, startNowSentinel),
            preset('In 15 minutes', formatStartAt(soon), Icons.timer_outlined,
                soon),
            preset('Tonight at 22:00', formatStartAt(tonight),
                Icons.nightlight_round, tonight),
            preset('Tomorrow at 08:00', formatStartAt(tomorrow),
                Icons.wb_sunny_outlined, tomorrow),
            preset('Pick a date & time', '', Icons.edit_calendar_outlined, null),
          ],
        ),
      ),
    );
  }
}
