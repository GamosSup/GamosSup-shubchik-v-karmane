import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _calendar = MethodChannel('shubchik/calendar');

class CalendarAgendaScreen extends StatefulWidget {
  const CalendarAgendaScreen({super.key});
  @override
  State<CalendarAgendaScreen> createState() => _CalendarAgendaScreenState();
}

class _CalendarAgendaScreenState extends State<CalendarAgendaScreen> {
  DateTime _from = DateUtils.dateOnly(DateTime.now());
  List<Map<Object?, Object?>>? _events;
  String? _selected;
  bool _loading = false;
  String _message = '';

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _message = '';
      _events = null;
      _selected = null;
    });
    final until = DateTime(_from.year, _from.month, _from.day + 30);
    try {
      final events = await _calendar.invokeListMethod<Map<Object?, Object?>>('listEvents', {
        'from': _from.millisecondsSinceEpoch,
        'until': until.millisecondsSinceEpoch,
      });
      if (mounted) setState(() => _events = events ?? []);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _message = error.code == 'calendar_denied'
          ? 'Разрешите доступ к календарю в настройках Android.'
          : 'Не удалось прочитать календарь устройства.');
    } on MissingPluginException {
      if (mounted) setState(() => _message = 'Календарь устройства недоступен в этой сборке.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _choose() async {
    final date = await showDatePicker(
      context: context, initialDate: _from,
      firstDate: DateTime(2000), lastDate: DateTime(2100),
    );
    if (date != null && mounted) {
      setState(() => _from = date);
      await _load();
    }
  }

  String _time(Map<Object?, Object?> event) {
    final labels = MaterialLocalizations.of(context);
    final allDay = event['allDay'] == true;
    final start = DateTime.fromMillisecondsSinceEpoch(event['start'] as int, isUtc: allDay);
    final date = labels.formatMediumDate(start);
    if (allDay) return '$date · Весь день';
    return '$date · ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(start))}';
  }

  @override
  Widget build(BuildContext context) {
    final events = _events;
    final calendars = events?.map((row) => row['calendar']).whereType<String>()
        .where((name) => name.isNotEmpty).toSet().toList() ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Календарь устройства')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('События видимых календарей за 30 дней. Они отображаются на телефоне.'),
          OutlinedButton.icon(
            onPressed: _loading ? null : _choose, icon: const Icon(Icons.date_range),
            label: Text(MaterialLocalizations.of(context).formatMediumDate(_from)),
          ),
          FilledButton(
            onPressed: _loading ? null : _load,
            child: Text(events == null ? 'Показать события' : 'Обновить'),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_message.isNotEmpty) Text(_message),
          if (calendars.length > 1) Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('Все календари'), selected: _selected == null,
              onSelected: (_) => setState(() => _selected = null)),
            for (final calendar in calendars)
              ChoiceChip(label: Text(calendar), selected: _selected == calendar,
                onSelected: (_) => setState(() => _selected = calendar)),
          ]),
          if (events?.isEmpty == true) const ListTile(title: Text('Событий нет')),
          for (final event in events ?? <Map<Object?, Object?>>[])
            if (_selected == null || event['calendar'] == _selected)
              ListTile(
                leading: const Icon(Icons.event),
                title: Text((event['title'] as String).isEmpty ? 'Событие' : event['title'] as String),
                subtitle: Text([_time(event), event['calendar']].whereType<String>().where((s) => s.isNotEmpty).join(' · ')),
              ),
        ],
      ),
    );
  }
}
