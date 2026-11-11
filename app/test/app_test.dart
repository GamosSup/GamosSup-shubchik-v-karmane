import 'package:flutter_test/flutter_test.dart';
import 'package:shubchik/main.dart';

void main() {
  testWidgets('Home lists the four planned modules', (tester) async {
    await tester.pumpWidget(const ShubchikApp());
    await tester.pumpAndSettle();
    for (final label in ['Музыка', 'Финансы', 'Планировщик', 'Развитие']) {
      expect(find.text(label), findsOneWidget);
    }
  });
}
