// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirror_stage_ego/core/services/twin_channel.dart';
import 'package:mirror_stage_ego/main.dart';

void main() {
  testWidgets('Digital twin shell renders status chips', (WidgetTester tester) async {
    await tester.pumpWidget(
      MirrorStageApp(
        channel: TwinChannel(connectImmediately: false),
      ),
    );

    expect(find.text('MIRROR STAGE'), findsOneWidget);
    expect(find.textContaining('내부망'), findsOneWidget);
    expect(find.textContaining('온라인 호스트'), findsOneWidget);
  });
}
