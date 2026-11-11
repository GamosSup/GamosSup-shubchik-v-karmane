import 'dart:convert';

import 'package:csv/csv.dart';

import 'guest_store.dart';

typedef BankRow = ({String key, String date, String title, int cents});

List<BankRow> parseBankCsv(String raw, {required String bank, required String account}) {
  final accountCode = account.trim().toLowerCase();
  if (!const {'sber', 'ozon', 'other'}.contains(bank) ||
      accountCode.isEmpty || accountCode.length > 64 || raw.length > 1000000) {
    throw const FormatException('Некорректный банк, счёт или размер файла');
  }
  final text = raw.replaceFirst('\ufeff', '').replaceAll('\r\n', '\n');
  final records = const CsvToListConverter(
    fieldDelimiter: ';', eol: '\n', shouldParseNumbers: false, allowInvalid: false,
  ).convert(text);
  if (records.isEmpty || records.length > 5001 ||
      records.first.map((field) => field.toString().trim().toLowerCase()).join(';') != 'id;date;title;amount') {
    throw const FormatException('Ожидается CSV с колонками id;date;title;amount');
  }
  final result = <String, BankRow>{};
  for (var index = 1; index < records.length; index++) {
    final cells = records[index].map((field) => field.toString().trim()).toList();
    if (cells.every((cell) => cell.isEmpty)) continue;
    if (cells.length != 4) throw FormatException('Строка ${index + 1}: ожидается 4 поля');
    final [id, date, title, amount] = cells;
    final dateValue = DateTime.tryParse(date);
    final validDate = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) &&
        dateValue != null && dateValue.toIso8601String().startsWith('${date}T');
    final negative = amount.startsWith('-');
    final magnitude = amount.startsWith('-') || amount.startsWith('+') ? amount.substring(1) : amount;
    final cents = parseCents(magnitude);
    if (id.isEmpty || id.length > 128 || !validDate || title.isEmpty ||
        title.length > 120 || cents == null) {
      throw FormatException('Строка ${index + 1}: проверьте ID, дату, название и сумму');
    }
    final key = jsonEncode([bank, accountCode, id]);
    final row = (key: key, date: date, title: title, cents: negative ? -cents : cents);
    if (result.containsKey(key) && result[key] != row) {
      throw FormatException('Строка ${index + 1}: один ID имеет разные данные');
    }
    result[key] = row;
  }
  if (result.isEmpty) throw const FormatException('В файле нет операций');
  return result.values.toList(growable: false);
}
