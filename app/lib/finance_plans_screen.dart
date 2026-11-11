import 'package:flutter/material.dart';

import 'guest_store.dart';

const _labels = {
  'account': 'Счета',
  'budget': 'Бюджеты',
  'goal': 'Накопления',
  'debt': 'Долги',
  'subscription': 'Подписки',
};

class FinancePlansScreen extends StatefulWidget {
  const FinancePlansScreen({super.key, required this.store});
  final GuestStore store;

  @override
  State<FinancePlansScreen> createState() => _FinancePlansScreenState();
}

typedef _Rows = List<Map<String, Object?>>;
typedef _PlanData = ({_Rows plans, _Rows ledger});
typedef _PlanDraft = ({String title, int target, int current, String? dueOn});

class _FinancePlansScreenState extends State<FinancePlansScreen> {
  late Future<_PlanData> _data;
  String _kind = 'account';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_PlanData> _load() async => (
    plans: await widget.store.entries('finance_items'),
    ledger: await widget.store.entries('ledger'),
  );

  void _refresh() => setState(() => _data = _load());

  Future<void> _save(Future<void> Function() action) async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _refresh();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить. Проверьте, что название уникально в этом разделе.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([Map<String, Object?>? row]) async {
    final kind = _kind;
    final draft = await showDialog<_PlanDraft>(
      context: context,
      builder: (_) => _PlanDialog(kind: kind, initial: row),
    );
    if (draft == null || !mounted) return;
    await _save(() => widget.store.saveFinanceItem(
      id: row?['id'] as int?, kind: kind, title: draft.title,
      target: draft.target, current: draft.current, dueOn: draft.dueOn,
    ));
  }

  Future<void> _remove(Map<String, Object?> row) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить запись финансового плана?'),
        content: Text(row['title'] as String),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await _save(() => widget.store.remove('finance_items', row['id'] as int));
    }
  }

  String _details(Map<String, Object?> item, _Rows ledger) {
    final target = item['target'] as int;
    final current = item['current'] as int;
    final title = item['title'];
    final due = item['due_on'];
    final month = DateTime.now().toIso8601String().substring(0, 7);
    final details = switch (_kind) {
      'account' => 'Баланс: ${formatMoney(ledger.where((row) => row['account'] == title).fold<int>(
        target, (total, row) => total + (row['cents'] as int),
      ))}',
      'budget' => 'Потрачено за месяц: ${formatMoney(ledger.where((row) {
        final date = row['posted_on'] ?? row['recorded_on'];
        return row['category'] == title && (row['cents'] as int) < 0 &&
            date is String && date.startsWith(month);
      }).fold<int>(0, (total, row) => total - (row['cents'] as int)))} из ${formatMoney(target)}',
      'goal' => 'Накоплено: ${formatMoney(current)} из ${formatMoney(target)}',
      'debt' => 'Остаток: ${formatMoney(current)} из ${formatMoney(target)}',
      _ => 'За месяц: ${formatMoney(target)}',
    };
    return due == null ? details : '$details · $due';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Финансовый план')),
    floatingActionButton: FloatingActionButton(
      onPressed: _busy ? null : () => _edit(),
      tooltip: 'Добавить', child: const Icon(Icons.add),
    ),
    body: FutureBuilder(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: TextButton(
          onPressed: _refresh, child: const Text('Не удалось открыть финансовый план. Повторить'),
        ));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        final rows = data.plans.where((row) => row['kind'] == _kind).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          children: [
            Wrap(spacing: 8, children: [
              for (final kind in _labels.entries) ChoiceChip(
                label: Text(kind.value), selected: _kind == kind.key,
                onSelected: (_) => setState(() => _kind = kind.key),
              ),
            ]),
            if (_kind == 'budget') const Text('Название бюджета должно совпадать с категорией расхода.'),
            if (_kind == 'account') const Text('В операциях указывайте название счёта, чтобы видеть его баланс.'),
            if (rows.isEmpty) const ListTile(title: Text('Записей пока нет')),
            if (_kind == 'subscription' && rows.isNotEmpty)
              ListTile(title: Text('За месяц: ${formatMoney(rows.fold<int>(0, (sum, row) => sum + (row['target'] as int)))}')),
            for (final row in rows) ListTile(
              title: Text(row['title'] as String), subtitle: Text(_details(row, data.ledger)),
              onTap: _busy ? null : () => _edit(row),
              trailing: IconButton(
                tooltip: 'Удалить', icon: const Icon(Icons.delete_outline),
                onPressed: _busy ? null : () => _remove(row),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _PlanDialog extends StatefulWidget {
  const _PlanDialog({required this.kind, this.initial});
  final String kind;
  final Map<String, Object?>? initial;
  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initial?['title'] as String?);
  late final _target = TextEditingController(text: _amountText(widget.initial?['target'] as int?));
  late final _current = TextEditingController(text: _amountText(widget.initial?['current'] as int?));
  late DateTime? _due = DateTime.tryParse(widget.initial?['due_on'] as String? ?? '');

  bool get _tracksProgress => widget.kind == 'goal' || widget.kind == 'debt';

  String? _amountText(int? value) => value == null ? null : formatMoney(value).replaceAll(' ₽', '').replaceAll('−', '-');

  int? _parse(String value, {bool allowZero = false, bool signed = false}) {
    final text = value.trim();
    if (allowZero && (text.isEmpty || RegExp(r'^0+(?:[,.]0{1,2})?$').hasMatch(text))) return 0;
    if (signed && text.startsWith('-')) {
      final magnitude = parseCents(text.substring(1));
      return magnitude == null ? null : -magnitude;
    }
    return parseCents(text);
  }

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    _current.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.kind == 'account';
    final label = switch (widget.kind) {
      'account' => 'Начальный остаток',
      'budget' => 'Лимит на месяц',
      'goal' => 'Целевая сумма',
      'debt' => 'Начальная сумма долга',
      _ => 'Стоимость в месяц',
    };
    return AlertDialog(
      title: Text(_labels[widget.kind]!),
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            controller: _title, maxLength: 80,
            decoration: const InputDecoration(labelText: 'Название'),
            validator: (text) => text!.trim().isEmpty ? 'Введите название' : null,
          ),
          TextFormField(
            controller: _target,
            keyboardType: TextInputType.numberWithOptions(decimal: true, signed: account),
            decoration: InputDecoration(labelText: label),
            validator: (text) => _parse(text!, allowZero: account, signed: account) == null ? 'Введите корректную сумму' : null,
          ),
          if (_tracksProgress) TextFormField(
            controller: _current,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: widget.kind == 'goal' ? 'Уже накоплено' : 'Остаток долга'),
            validator: (text) => _parse(text!, allowZero: true) == null ? 'Введите корректную сумму' : null,
          ),
          if (!account && widget.kind != 'budget') Wrap(children: [
            TextButton(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context, initialDate: _due ?? DateTime.now(),
                  firstDate: DateTime(2000), lastDate: DateTime(2100),
                );
                if (date != null && mounted) setState(() => _due = date);
              },
              child: Text(_due == null ? 'Выбрать дату' : MaterialLocalizations.of(context).formatMediumDate(_due!)),
            ),
            if (_due != null) IconButton(
              tooltip: 'Убрать дату', onPressed: () => setState(() => _due = null),
              icon: const Icon(Icons.clear),
            ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            final target = _parse(_target.text, allowZero: account, signed: account)!;
            final current = widget.kind == 'debt' && _current.text.trim().isEmpty
                ? target : _parse(_current.text, allowZero: true)!;
            Navigator.pop(context, (
              title: _title.text.trim(), target: target, current: current,
              dueOn: _due?.toIso8601String().substring(0, 10),
            ));
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
