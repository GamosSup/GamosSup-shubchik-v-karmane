import 'package:flutter_test/flutter_test.dart';
import 'package:shubchik/account_workspace.dart';

void main() {
  const clean = (revision: 2, base: 'base', local: 'base');
  const edited = (revision: 2, base: 'base', local: 'phone');
  test('An unchanged device downloads cloud edits', () {
    expect(compareSnapshots(clean, (revision: 3, payload: 'cloud')), SyncDecision.download);
  });
  test('A dirty device uploads only against its known revision', () {
    expect(compareSnapshots(edited, (revision: 2, payload: 'base')), SyncDecision.upload);
    expect(compareSnapshots(edited, (revision: 3, payload: 'cloud')), SyncDecision.conflict);
  });
  test('Retry after a committed upload recognizes the same payload', () {
    expect(compareSnapshots(edited, (revision: 3, payload: 'phone')), SyncDecision.unchanged);
  });
}
