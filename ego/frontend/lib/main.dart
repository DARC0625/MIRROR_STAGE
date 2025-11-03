import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/models/twin_models.dart';
import 'core/services/twin_channel.dart';

void main() {
  runApp(const MirrorStageApp());
}

class MirrorStageApp extends StatelessWidget {
  const MirrorStageApp({super.key, this.channel});

  final TwinChannel? channel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00B7C2),
      brightness: Brightness.dark,
    );

    final baseTheme = ThemeData(
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF05080D),
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'MIRROR STAGE',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        textTheme: GoogleFonts.ibmPlexSansTextTheme(baseTheme.textTheme).apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF05080D),
          foregroundColor: colorScheme.onBackground,
          elevation: 0,
        ),
      ),
      home: DigitalTwinShell(channel: channel),
    );
  }
}

class DigitalTwinShell extends StatefulWidget {
  const DigitalTwinShell({super.key, this.channel});

  final TwinChannel? channel;

  @override
  State<DigitalTwinShell> createState() => _DigitalTwinShellState();
}

class _DigitalTwinShellState extends State<DigitalTwinShell> {
  late final TwinChannel _channel;
  late final bool _ownsChannel;
  late final Stream<TwinStateFrame> _stream;
  TwinStateFrame? _lastFrame;

  @override
  void initState() {
    super.initState();
    _ownsChannel = widget.channel == null;
    _channel = widget.channel ?? TwinChannel();
    _stream = _channel.stream();
  }

  @override
  void dispose() {
    if (_ownsChannel) {
      _channel.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TwinStateFrame>(
      stream: _stream,
      initialData: TwinStateFrame.empty(),
      builder: (context, snapshot) {
        final candidate = snapshot.data;
        if (candidate != null && candidate.hosts.isNotEmpty) {
          _lastFrame = candidate;
        }
        final frame = candidate?.hosts.isNotEmpty == true
            ? candidate!
            : (_lastFrame ?? TwinStateFrame.empty());

        return Scaffold(
          appBar: AppBar(
            title: const Text('MIRROR STAGE'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    alignment: WrapAlignment.end,
                    children: [
                      const _StatusChip(label: '내부망', value: '10.0.0.0/24'),
                      _StatusChip(
                        label: '온라인 호스트',
                        value: '${frame.onlineHosts}/${frame.totalHosts}',
                      ),
                      _StatusChip(
                        label: '총 링크 부하',
                        value: '${(frame.linkUtilization * 100).clamp(0, 100).toStringAsFixed(0)}%',
                      ),
                      _StatusChip(
                        label: '총 스루풋',
                        value: '${frame.estimatedThroughput.toStringAsFixed(2)} Gbps',
                      ),
                      _StatusChip(
                        label: '총 링크 용량',
                        value: frame.totalLinkCapacity > 0
                            ? '${frame.totalLinkCapacity.toStringAsFixed(2)} Gbps'
                            : 'N/A',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 1080;

              if (isWide) {
                return Row(
                  children: [
                    _Sidebar(frame: frame),
                    Expanded(
                      child: _TwinViewport(
                        frame: frame,
                        height: constraints.maxHeight,
                      ),
                    ),
                    _InsightPanel(frame: frame),
                  ],
                );
              }

              return Column(
                children: [
                  Expanded(
                    child: _TwinViewport(
                      frame: frame,
                      height: constraints.maxHeight * .65,
                    ),
                  ),
                  _InsightPanel(frame: frame),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.frame});

  final TwinStateFrame frame;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: Color(0xFF11141D)),
        ),
        gradient: LinearGradient(
          colors: [Color(0xFF060910), Color(0xFF020307)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '실시간 개요',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 24),
          _MetricTile(
            label: '평균 CPU 사용률',
            value: '${frame.averageCpuLoad.toStringAsFixed(1)}%',
          ),
          _MetricTile(
            label: '평균 메모리 사용률',
            value: '${frame.averageMemoryLoad.toStringAsFixed(1)}%',
          ),
          _MetricTile(
            label: '실시간 스루풋',
            value: '${frame.estimatedThroughput.toStringAsFixed(2)} Gbps',
            caption: frame.maxHostThroughput > 0
                ? '호스트 최대 ${frame.maxHostThroughput.toStringAsFixed(2)} Gbps'
                : null,
          ),
          _MetricTile(
            label: '평균 링크 활용률',
            value: '${(frame.linkUtilization * 100).clamp(0, 100).toStringAsFixed(1)}%',
            caption: frame.totalLinkCapacity > 0
                ? '총 용량 ${frame.totalLinkCapacity.toStringAsFixed(2)} Gbps'
                : null,
          ),
          const SizedBox(height: 32),
          Text(
            'VR 씬 전환',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white70,
                  letterSpacing: 0.2,
                ),
          ),
          const SizedBox(height: 12),
          ...[
            '글로벌 토폴로지',
            '랙 / 룸 뷰',
            '온도 히트맵',
            '자동화 타임라인',
          ].map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _NavButton(label: entry),
            ),
          ),
          const Spacer(),
          Text(
            '생성 시각: ${frame.generatedAt.toLocal().toIso8601String()}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _TwinViewport extends StatelessWidget {
  const _TwinViewport({required this.frame, required this.height});

  final TwinStateFrame frame;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: height,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF061728), Color(0xFF03101D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: CustomPaint(
            painter: _TwinScenePainter(frame),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _InsightPanel extends StatelessWidget {
  const _InsightPanel({required this.frame});

  final TwinStateFrame frame;

  @override
  Widget build(BuildContext context) {
    final topHosts = frame.activeHosts.take(4).toList();
    return Container(
      width: 320,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: Color(0xFF11141D)),
        ),
        gradient: LinearGradient(
          colors: [Color(0xFF080C14), Color(0xFF020408)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '상위 리소스 소비 호스트',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 18),
          if (topHosts.isEmpty)
            const _ActivityTile(
              timestamp: '대기 중',
              summary: '텔레메트리를 수신하면 여기에 최신 이벤트가 표시됩니다.',
            )
          else
            ...topHosts.map(
              (host) => _ActivityTile(
                timestamp: host.lastSeen.toLocal().toIso8601String(),
                summary: _hostSummary(host),
              ),
            ),
        ],
      ),
    );
  }

  String _hostSummary(TwinHost host) {
    final cpu = host.metrics.cpuLoad.toStringAsFixed(1);
    final memory = host.metrics.memoryUsedPercent.toStringAsFixed(1);
    final throughput = host.metrics.netThroughputGbps;
    final capacity = host.metrics.netCapacityGbps;

    final segments = <String>[
      '${host.displayName} (${host.ip})',
      'CPU $cpu%',
      'RAM $memory%',
    ];

    if (throughput != null && throughput > 0) {
      final head = throughput.toStringAsFixed(2);
      String netText = 'NET $head Gbps';
      if (capacity != null && capacity > 0) {
        netText = 'NET $head / ${capacity.toStringAsFixed(2)} Gbps';
      }
      segments.add(netText);
    }

    return segments.join(' — ');
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value, this.caption});

  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                caption!,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: const BorderSide(color: Color(0xFF1A1F2B)),
        backgroundColor: const Color(0xFF0A101A),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () {},
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(label),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.timestamp, required this.summary});

  final String timestamp;
  final String summary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timestamp,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary,
                  style: const TextStyle(color: Colors.white70, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      backgroundColor: const Color(0xFF0C121E),
      labelPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: const BorderSide(color: Color(0xFF1B2333)),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.tealAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TwinScenePainter extends CustomPainter {
  _TwinScenePainter(this.frame);

  final TwinStateFrame frame;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    _paintLinks(canvas, size);
    _paintHosts(canvas, size);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0E2032)
      ..strokeWidth = 0.6;

    const spacing = 36.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    final haloPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF0B2234), Colors.transparent],
        radius: 0.8,
      ).createShader(Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide * 0.55));
    canvas.drawCircle(size.center(Offset.zero), size.shortestSide * 0.55, haloPaint);
  }

  void _paintLinks(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final scale = _scaleFactor(size);
    final hosts = {for (final host in frame.hosts) host.hostname: host};

    for (final link in frame.links) {
      final source = hosts[link.source];
      final target = hosts[link.target];
      if (source == null || target == null) continue;

      final sourcePoint = _projectPoint(source.position, center, scale);
      final targetPoint = _projectPoint(target.position, center, scale);

      final utilization = link.utilization.clamp(0, 1);
      final color = Color.lerp(
        Colors.tealAccent,
        Colors.deepOrangeAccent,
        utilization.toDouble(),
      )!;

      final paint = Paint()
        ..color = color.withOpacity(0.65)
        ..strokeWidth = 2 + utilization * 3
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(sourcePoint.dx, sourcePoint.dy)
        ..quadraticBezierTo(
          (sourcePoint.dx + targetPoint.dx) / 2,
          math.min(sourcePoint.dy, targetPoint.dy) - 32,
          targetPoint.dx,
          targetPoint.dy,
        );

      canvas.drawPath(path, paint);
    }
  }

  void _paintHosts(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final scale = _scaleFactor(size);

    for (final host in frame.hosts) {
      final position = _projectPoint(host.position, center, scale);
      final status = host.status;
      final isCore = host.isCore;

      final color = switch (status) {
        TwinHostStatus.online => Colors.tealAccent,
        TwinHostStatus.stale => Colors.amberAccent,
        TwinHostStatus.offline => Colors.redAccent,
      };

      final radius = isCore ? 20.0 : 10.0 + host.metrics.cpuLoad.clamp(0, 100) * 0.06;

      final nodePaint = Paint()
        ..color = color.withOpacity(isCore ? 0.9 : 0.75)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(position, radius, nodePaint);

      if (!isCore) {
        canvas.drawCircle(
          position,
          radius + 6,
          Paint()
            ..color = color.withOpacity(0.18)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }

      final textPainter = TextPainter(
        text: TextSpan(
          text: host.displayLabel,
          style: TextStyle(
            color: Colors.white.withOpacity(0.85),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 160);

      textPainter.paint(
        canvas,
        position + Offset(-textPainter.width / 2, radius + 6),
      );
    }
  }

  double _scaleFactor(Size size) {
    final radius = frame.maxRadius;
    if (radius <= 0) return 1;
    final margin = 64.0;
    return ((size.shortestSide / 2) - margin) / radius;
  }

  Offset _projectPoint(TwinPosition position, Offset center, double scale) {
    final x = center.dx + position.x * scale;
    final y = center.dy + position.z * scale - position.y * 0.8;
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant _TwinScenePainter oldDelegate) => oldDelegate.frame != frame;
}
