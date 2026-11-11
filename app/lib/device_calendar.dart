import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _calendar = MethodChannel('shubchik/calendar');

Future<void> composeCalendarEvent(BuildContext context, String title) async {
  final today = DateUtils.dateOnly(DateTime.now());
  final day = await showDatePicker(
    context: context,
    firstDate: today,
    lastDate: DateTime(today.year + 5),
    initialDate: today,
  );
  if (day == null || !context.mounted) return;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
  if (time == null || !context.mounted) return;
  final start = DateTime(day.year, day.month, day.day, time.hour, time.minute);
  final end = start.add(const Duration(hours: 1));
  try {
    await _calendar.invokeMethod<void>('composeEvent', {
      'title': title,
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
    });
  } on PlatformException {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Календарь устройства недоступен')),
    );
  } on MissingPluginException {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Календарь устройства недоступен в этой сборке')),
    );
  }
}
