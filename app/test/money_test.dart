import 'package:flutter_test/flutter_test.dart';
import 'package:shubchik/guest_store.dart';

void main() {
  test('Rubles convert to integer kopecks without rounding', () {
    expect(parseCents(' 123,40 '), 12340);
    expect(parseCents('0.01'), 1);
    expect(parseCents('5'), 500);
    expect(parseCents('0,00'), isNull);
    expect(parseCents('1,234'), isNull);
    expect(formatMoney(-5), '−0,05 ₽');
  });
}
