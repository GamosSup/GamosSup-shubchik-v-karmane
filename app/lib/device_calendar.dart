import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _calendar = MethodChannel('shubchik/calendar');
const _reminders = MethodChannel('shubchik/reminders');

Future<DateTime?> _chooseTime(BuildContext context, String? dueOn) async {
  final today = DateUtils.dateOnly(DateTime.now());
  final limit = DateTime(today.year + 5);
  final due = DateTime.tryParse(dueOn ?? '');
  final initial = due == null || due.isBefore(today) || due.isAfter(limit) ? today : due;
  final day = await showDatePicker(
    context: context, firstDate: today, lastDate: limit, initialDate: initial,
  );
  if (day == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
  if (time == null || !context.mounted) return null;
  return DateTime(day.year, day.month, day.day, time.hour, time.minute);
}

void _message(BuildContext context, String message) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}

Future<void> composeCalendarEvent(BuildContext context, String title, {String? dueOn}) async {
  final start = await _chooseTime(context, dueOn);
  if (start == null || !context.mounted) return;
  final end = start.add(const Duration(hours: 1));
  try {
    await _calendar.invokeMethod<void>('composeEvent', {
      'title': title, 'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
    });
  } on PlatformException {
    if (context.mounted) _message(context, 'Календарь устройства недоступен');
  } on MissingPluginException {
    if (context.mounted) _message(context, 'Календарь устройства недоступен в этой сборке');
  }
}

Future<void> scheduleTaskReminder(BuildContext context, String key, String? dueOn) async {
  final time = await _chooseTime(context, dueOn);
  if (time == null || !context.mounted) return;
  if (!time.isAfter(DateTime.now())) {
    _message(context, 'Выберите время в будущем');
    return;
  }
  try {
    await _reminders.invokeMethod<void>('schedule', {'key': key, 'time': time.millisecondsSinceEpoch});
    if (context.mounted) _message(context, 'Напоминание сохранено. Android может доставить его с задержкой.');
  } on PlatformException catch (error) {
    if (context.mounted) _message(context, error.code == 'notifications_disabled'
        ? 'Разрешите уведомления для приложения'
        : 'Не удалось запланировать напоминание');
  } on MissingPluginException {
    if (context.mounted) _message(context, 'Напоминания недоступны в этой сборке');
  }
}

Future<bool> cancelTaskReminder(String key) async {
  try {
    await _reminders.invokeMethod<void>('cancel', {'key': key});
    return true;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
