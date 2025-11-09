// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:mirror_stage_ego/core/services/twin_channel.dart';
import 'package:mirror_stage_ego/main.dart';

void main() {
  testWidgets('Digital twin shell renders status chips', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MirrorStageApp(channel: TwinChannel(connectImmediately: false)),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('MIRROR STAGE'), findsOneWidget);
    expect(find.textContaining('전역 메트릭'), findsOneWidget);
    expect(find.text('위젯'), findsOneWidget);
    expect(find.text('노드를 선택하여 링크를 확인하세요.'), findsOneWidget);
  });
}
