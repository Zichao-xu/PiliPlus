import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:PiliPlus/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App 启动测试', () {
    testWidgets('app launches and shows main tabs', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // 至少能看到「动态」或「我的」字样
      final hasDynamic = find.text('动态').evaluate().isNotEmpty;
      final hasMine = find.text('我的').evaluate().isNotEmpty;
      expect(hasDynamic || hasMine, isTrue);
    });
  });
}
