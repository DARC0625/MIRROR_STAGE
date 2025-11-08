import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'core/models/twin_models.dart';
import 'core/services/twin_channel.dart';

enum TwinViewportMode { topology, heatmap }

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
      fontFamily: 'Pretendard',
    );

    final textTheme = baseTheme.textTheme.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    );

    return MaterialApp(
      title: 'MIRROR STAGE',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(textTheme: textTheme),
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
  TwinViewportMode _viewportMode = TwinViewportMode.topology;
  String? _selectedHostName;

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

  void _setViewportMode(TwinViewportMode mode) {
    if (_viewportMode == mode) return;
    setState(() => _viewportMode = mode);
  }

  void _selectHost(String hostname) {
    if (_selectedHostName == hostname) {
      return;
    }
    setState(() => _selectedHostName = hostname);
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

        TwinHost? selectedHost = _selectedHostName != null
            ? frame.hostByName(_selectedHostName!)
            : null;
        if (_selectedHostName != null && selectedHost == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _selectedHostName = null);
          });
        }

        final heatMax = frame.maxCpuTemperature > 0
            ? frame.maxCpuTemperature
            : 100.0;

        return Scaffold(
          backgroundColor: const Color(0xFF05080D),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 1200;
                final stage = _TwinStage(
                  frame: frame,
                  mode: _viewportMode,
                  selectedHost: selectedHost,
                  heatMax: heatMax,
                  onSelectHost: _selectHost,
                  onClearSelection: _clearSelection,
                );
                final leftPanel = _Sidebar(
                  frame: frame,
                  mode: _viewportMode,
                  onModeChange: _setViewportMode,
                  selectedHost: selectedHost,
                );
                final rightPanel = _StatusSidebar(
                  frame: frame,
                  selectedHost: selectedHost,
                );

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 320, child: leftPanel),
                      Expanded(child: stage),
                      SizedBox(width: 360, child: rightPanel),
                    ],
                  );
                }

                return Column(
                  children: [
                    Expanded(child: stage),
                    SizedBox(
                      height: (constraints.maxHeight * 0.35).clamp(
                        260.0,
                        420.0,
                      ),
                      child: leftPanel,
                    ),
                    SizedBox(
                      height: (constraints.maxHeight * 0.4).clamp(280.0, 460.0),
                      child: rightPanel,
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _clearSelection() {
    if (_selectedHostName != null) {
      setState(() => _selectedHostName = null);
    }
  }
}

class _Sidebar extends StatefulWidget {
  const _Sidebar({
    required this.frame,
    required this.mode,
    required this.onModeChange,
    required this.selectedHost,
  });

  final TwinStateFrame frame;
  final TwinViewportMode mode;
  final ValueChanged<TwinViewportMode> onModeChange;
  final TwinHost? selectedHost;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  late final PageController _controller;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.9);
  }

  @override
  void didUpdateWidget(covariant _Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedHost?.hostname != oldWidget.selectedHost?.hostname) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller.jumpToPage(0);
        setState(() => _currentPage = 0);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final statusChips = [
      _StatusChip(label: '내부망', value: '10.0.0.0/24'),
      _StatusChip(
        label: '온라인',
        value: '${widget.frame.onlineHosts}/${widget.frame.totalHosts}',
      ),
      _StatusChip(
        label: 'CPU',
        value: '${widget.frame.averageCpuLoad.toStringAsFixed(1)}%',
      ),
      _StatusChip(
        label: '메모리',
        value: widget.frame.totalMemoryCapacityGb > 0
            ? '${widget.frame.totalMemoryUsedGb.toStringAsFixed(1)}/${widget.frame.totalMemoryCapacityGb.toStringAsFixed(1)} GB'
            : '${widget.frame.averageMemoryLoad.toStringAsFixed(1)}%',
      ),
    ];

    final pages = _buildPages();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF060910), Color(0xFF020307)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '작전 콘솔',
                style: theme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              _ViewModeToggle(
                mode: widget.mode,
                onModeChange: widget.onModeChange,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: statusChips),
          const SizedBox(height: 20),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: pages.length,
              onPageChanged: (value) => setState(() => _currentPage = value),
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: pages[index],
              ),
            ),
          ),
          if (pages.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _DotsIndicator(count: pages.length, index: _currentPage),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildPages() {
    final cards = <Widget>[_SidebarOverviewCard(frame: widget.frame)];
    final host = widget.selectedHost;
    if (host != null) {
      cards.add(_GlassTile(child: _HostVitalsBar(host: host)));
      cards.add(_GlassTile(child: _SelectedTelemetryPanel(host: host)));
    } else {
      cards.add(const _GlassTile(child: _SidebarPlaceholder()));
    }
    return cards;
  }
}

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.mode, required this.onModeChange});

  final TwinViewportMode mode;
  final ValueChanged<TwinViewportMode> onModeChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x331B2333)),
      ),
      child: ToggleButtons(
        isSelected: [
          mode == TwinViewportMode.topology,
          mode == TwinViewportMode.heatmap,
        ],
        onPressed: (index) => onModeChange(TwinViewportMode.values[index]),
        borderRadius: BorderRadius.circular(999),
        constraints: const BoxConstraints(minHeight: 38, minWidth: 110),
        fillColor: const Color(0xFF0D2032),
        selectedColor: Colors.tealAccent,
        color: Colors.white70,
        borderColor: Colors.transparent,
        selectedBorderColor: Colors.tealAccent.withValues(alpha: 0.4),
        children: const [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.travel_explore, size: 16),
              SizedBox(width: 6),
              Text('토폴로지'),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.heat_pump, size: 16),
              SizedBox(width: 6),
              Text('히트맵'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusSidebar extends StatelessWidget {
  const _StatusSidebar({required this.frame, required this.selectedHost});

  final TwinStateFrame frame;
  final TwinHost? selectedHost;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF020408), Color(0xFF060910)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(left: BorderSide(color: Color(0x22111B2D))),
      ),
      child: _HostOverlay(frame: frame, host: selectedHost),
    );
  }
}

class _TwinViewport extends StatelessWidget {
  const _TwinViewport({
    required this.frame,
    required this.height,
    required this.mode,
    required this.selectedHost,
    required this.heatMax,
    required this.onSelectHost,
    required this.onClearSelection,
    required this.cameraFocus,
    required this.linkPulse,
  });

  final TwinStateFrame frame;
  final double height;
  final TwinViewportMode mode;
  final String? selectedHost;
  final double heatMax;
  final ValueChanged<String> onSelectHost;
  final VoidCallback onClearSelection;
  final TwinPosition cameraFocus;
  final double linkPulse;

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
          child: LayoutBuilder(
            builder: (context, viewportConstraints) {
              final size = Size(
                viewportConstraints.maxWidth,
                viewportConstraints.maxHeight,
              );
              final center = size.center(Offset.zero);
              final scale = twinScaleFactor(frame, size);

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final tap = details.localPosition;
                  TwinHost? nearest;
                  double minDistance = double.infinity;
                  for (final host in frame.hosts) {
                    final point = twinProjectPoint(
                      host.position,
                      center,
                      scale,
                    );
                    final radius = hostBubbleRadius(host);
                    final distance = (tap - point).distance;
                    if (distance <= radius + 14 && distance < minDistance) {
                      nearest = host;
                      minDistance = distance;
                    }
                  }
                  if (nearest != null) {
                    onSelectHost(nearest.hostname);
                  } else {
                    onClearSelection();
                  }
                },
                child: CustomPaint(
                  painter: _TwinScenePainter(
                    frame,
                    mode: mode,
                    selectedHost: selectedHost,
                    heatMax: heatMax,
                    cameraFocus: cameraFocus,
                    linkPulse: linkPulse,
                  ),
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TwinStage extends StatefulWidget {
  const _TwinStage({
    required this.frame,
    required this.mode,
    required this.selectedHost,
    required this.heatMax,
    required this.onSelectHost,
    required this.onClearSelection,
  });

  final TwinStateFrame frame;
  final TwinViewportMode mode;
  final TwinHost? selectedHost;
  final double heatMax;
  final ValueChanged<String> onSelectHost;
  final VoidCallback onClearSelection;

  @override
  State<_TwinStage> createState() => _TwinStageState();
}

class _TwinStageState extends State<_TwinStage> with TickerProviderStateMixin {
  late final AnimationController _cameraController;
  late final AnimationController _linkPulseController;
  late final Animation<double> _linkPulseAnimation;
  TwinPosition _cameraFrom = TwinPosition.zero;
  TwinPosition _cameraTo = TwinPosition.zero;

  @override
  void initState() {
    super.initState();
    _cameraController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..value = 1;
    _cameraTo = widget.selectedHost?.position ?? TwinPosition.zero;
    _cameraFrom = _cameraTo;

    _linkPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _linkPulseAnimation = CurvedAnimation(
      parent: _linkPulseController,
      curve: Curves.easeInOutSine,
    );
  }

  @override
  void didUpdateWidget(covariant _TwinStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedHost?.hostname != oldWidget.selectedHost?.hostname) {
      _retargetCamera(widget.selectedHost?.position);
    }
    if (widget.mode != oldWidget.mode &&
        widget.mode == TwinViewportMode.topology) {
      _retargetCamera(widget.selectedHost?.position);
    }
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _linkPulseController.dispose();
    super.dispose();
  }

  void _retargetCamera(TwinPosition? target) {
    _cameraFrom = _currentCameraFocus;
    _cameraTo = target ?? TwinPosition.zero;
    _cameraController
      ..stop()
      ..reset()
      ..forward();
  }

  TwinPosition get _currentCameraFocus => TwinPosition.lerp(
    _cameraFrom,
    _cameraTo,
    Curves.easeOutCubic.transform(_cameraController.value),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: _cameraController,
          builder: (context, _) {
            final focus = _currentCameraFocus;
            return Stack(
              children: [
                Positioned.fill(
                  child: _TwinViewport(
                    frame: widget.frame,
                    height: constraints.maxHeight,
                    mode: widget.mode,
                    selectedHost: widget.selectedHost?.hostname,
                    heatMax: widget.heatMax,
                    onSelectHost: widget.onSelectHost,
                    onClearSelection: widget.onClearSelection,
                    cameraFocus: focus,
                    linkPulse: _linkPulseAnimation.value,
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: _HostChipRail(
                      hosts: widget.frame.hosts,
                      selectedHost: widget.selectedHost?.hostname,
                      onSelect: widget.onSelectHost,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _AnalogGauge extends StatefulWidget {
  const _AnalogGauge({
    required this.label,
    required this.value,
    required this.maxValue,
    this.units = '',
    this.decimals = 1,
    this.subtitle,
    this.size = 170,
    this.startColor = const Color(0xFF22D3EE),
    this.endColor = Colors.deepOrangeAccent,
  });

  final String label;
  final double value;
  final double maxValue;
  final String units;
  final int decimals;
  final String? subtitle;
  final double size;
  final Color startColor;
  final Color endColor;

  @override
  State<_AnalogGauge> createState() => _AnalogGaugeState();
}

class _AnalogGaugeState extends State<_AnalogGauge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      lowerBound: 0,
      upperBound: 1,
      value: _normalized(widget.value),
      duration: const Duration(milliseconds: 600),
    );
  }

  double _normalized(double value) {
    if (widget.maxValue <= 0) return 0;
    return (value / widget.maxValue).clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(covariant _AnalogGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _normalized(widget.value);
    if ((_controller.value - target).abs() < 0.001) {
      return;
    }
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final valueText = widget.value.toStringAsFixed(widget.decimals);
    final units = widget.units.isNotEmpty ? ' ${widget.units}' : '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: textTheme.titleSmall?.copyWith(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final normalized = _controller.value;
              final color =
                  Color.lerp(widget.startColor, widget.endColor, normalized) ??
                  widget.startColor;
              return CustomPaint(
                painter: _GaugePainter(normalized: normalized, color: color),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '$valueText$units',
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (widget.subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              widget.subtitle!,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({required this.normalized, required this.color});

  final double normalized;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 12;
    const startAngle = 3 * math.pi / 4;
    const sweepAngle = 3 * math.pi / 2;
    const stroke = 10.0;

    final arcRect = Rect.fromCircle(center: center, radius: radius);

    final backgroundPaint = Paint()
      ..color = const Color(0xFF1C2A3A)
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(arcRect, startAngle, sweepAngle, false, backgroundPaint);

    final progressPaint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      arcRect,
      startAngle,
      sweepAngle * normalized,
      false,
      progressPaint,
    );

    final pointerPaint = Paint()
      ..color = color
      ..strokeWidth = stroke * 0.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final pointerAngle = startAngle + sweepAngle * normalized;
    final pointerLength = radius - stroke * 0.8;
    final pointerOffset = Offset(
      center.dx + pointerLength * math.cos(pointerAngle),
      center.dy + pointerLength * math.sin(pointerAngle),
    );
    canvas.drawLine(center, pointerOffset, pointerPaint);
    canvas.drawCircle(center, stroke * 0.7, Paint()..color = Colors.white24);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.normalized != normalized || oldDelegate.color != color;
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
      label: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.tealAccent,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarOverviewCard extends StatelessWidget {
  const _SidebarOverviewCard({required this.frame});

  final TwinStateFrame frame;

  @override
  Widget build(BuildContext context) {
    final widgets = [
      _InfoWidgetConfig(
        title: '평균 CPU',
        child: _AnalogGauge(
          label: '평균 CPU',
          value: frame.averageCpuLoad.clamp(0, 100).toDouble(),
          maxValue: 100,
          units: '%',
          decimals: 1,
          startColor: Colors.lightBlueAccent,
          endColor: Colors.deepOrangeAccent,
          subtitle: frame.averageCpuTemperature > 0
              ? '온도 ${frame.averageCpuTemperature.toStringAsFixed(1)}℃'
              : null,
          size: 120,
        ),
      ),
      _InfoWidgetConfig(
        title: '메모리 사용률',
        child: _AnalogGauge(
          label: '메모리',
          value: frame.memoryUtilizationPercent.clamp(0, 100).toDouble(),
          maxValue: 100,
          units: '%',
          decimals: 1,
          startColor: const Color(0xFF38BDF8),
          endColor: Colors.deepOrangeAccent,
          subtitle: frame.totalMemoryCapacityGb > 0
              ? '${frame.totalMemoryUsedGb.toStringAsFixed(1)}/${frame.totalMemoryCapacityGb.toStringAsFixed(1)} GB'
              : null,
          size: 120,
        ),
      ),
      _InfoWidgetConfig(
        title: '링크 상태',
        child: _TrendTile(
          value: '${frame.estimatedThroughput.toStringAsFixed(2)} Gbps',
          caption: frame.totalLinkCapacity > 0
              ? '용량 ${frame.totalLinkCapacity.toStringAsFixed(2)} Gbps'
              : '용량 정보 없음',
          trend: (frame.linkUtilization * 100).clamp(0.0, 100.0),
        ),
      ),
      _InfoWidgetConfig(
        title: '온도',
        child: _TrendTile(
          value: frame.maxCpuTemperature > 0
              ? '${frame.maxCpuTemperature.toStringAsFixed(1)}℃'
              : 'N/A',
          caption: '평균 ${frame.averageCpuTemperature.toStringAsFixed(1)}℃',
          trend: (frame.averageCpuTemperature / 110).clamp(0.0, 1.0) * 100,
        ),
      ),
    ];

    return SingleChildScrollView(
      child: _GlassTile(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '전역 메트릭',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: widgets
                  .map(
                    (config) => SizedBox(
                      width: 200,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            config.title,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          config.child,
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarPlaceholder extends StatelessWidget {
  const _SidebarPlaceholder();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: Center(
        child: Text(
          '노드를 선택하면 실시간 텔레메트리를 확인할 수 있습니다.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _DotsIndicator extends StatelessWidget {
  const _DotsIndicator({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        count,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: i == index ? 18 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: i == index
                ? Colors.tealAccent
                : Colors.white.withValues(alpha: 0.25),
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF111A29),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF1F2B3D)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white54),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _HostOverlay extends StatefulWidget {
  const _HostOverlay({required this.frame, required this.host});

  final TwinStateFrame frame;
  final TwinHost? host;

  @override
  State<_HostOverlay> createState() => _HostOverlayState();
}

class _HostOverlayState extends State<_HostOverlay> {
  final Map<String, _MetricHistoryBuffer> _historyByHost = {};
  final Map<String, DateTime> _lastTimestampByHost = {};

  @override
  void initState() {
    super.initState();
    _ingestSample();
  }

  @override
  void didUpdateWidget(covariant _HostOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ingestSample();
  }

  void _ingestSample() {
    final host = widget.host;
    if (host == null) {
      return;
    }

    final timestamp = widget.frame.generatedAt;
    final last = _lastTimestampByHost[host.hostname];
    if (last != null && !timestamp.isAfter(last)) {
      return;
    }

    final buffer = _historyByHost.putIfAbsent(
      host.hostname,
      _MetricHistoryBuffer.new,
    );
    final previous = buffer.latest;
    final throughput = host.metrics.netThroughputGbps ?? previous?.throughput;
    final temperature =
        host.cpuTemperature ?? host.gpuTemperature ?? previous?.temperature;

    buffer.add(
      _MetricSample(
        timestamp: timestamp,
        cpu: host.metrics.cpuLoad,
        memory: host.metrics.memoryUsedPercent,
        throughput: throughput,
        temperature: temperature,
      ),
    );
    _lastTimestampByHost[host.hostname] = timestamp;
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final samples = host != null
        ? _historyByHost[host.hostname]?.samples ?? const <_MetricSample>[]
        : const <_MetricSample>[];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: host == null
          ? const _HostOverlayPlaceholder(key: ValueKey('empty'))
          : _HostOverlayCard(
              key: ValueKey(host.hostname),
              host: host,
              samples: samples,
            ),
    );
  }
}

class _HostOverlayCard extends StatefulWidget {
  const _HostOverlayCard({
    super.key,
    required this.host,
    required this.samples,
  });

  final TwinHost host;
  final List<_MetricSample> samples;

  @override
  State<_HostOverlayCard> createState() => _HostOverlayCardState();
}

class _HostOverlayCardState extends State<_HostOverlayCard> {
  late final PageController _controller;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final sections = _buildSections();
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xF00D141F),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0x221B2333)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OverlayHeader(host: widget.host, theme: theme),
              const SizedBox(height: 16),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: sections.length,
                  onPageChanged: (value) => setState(() => _page = value),
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: sections[index],
                  ),
                ),
              ),
              if (sections.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _DotsIndicator(count: sections.length, index: _page),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSections() {
    final host = widget.host;
    final samples = widget.samples;
    return [
      _RealtimeTelemetryCard(host: host, samples: samples),
      _SystemSummaryPanel(host: host),
      _ProcessPanel(host: host),
      _InterfacePanel(host: host),
      _StoragePanel(host: host),
    ];
  }
}

class _HostOverlayPlaceholder extends StatelessWidget {
  const _HostOverlayPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x221B2333)),
        color: const Color(0x110D141F),
      ),
      alignment: Alignment.center,
      child: const Text(
        '노드를 선택하면 시스템 상태가 표시됩니다.',
        style: TextStyle(color: Colors.white38),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _HostVitalsBar extends StatelessWidget {
  const _HostVitalsBar({required this.host});

  final TwinHost host;

  @override
  Widget build(BuildContext context) {
    final osLabel = _joinNonEmpty([
      host.hardware.osDistro,
      host.hardware.osRelease,
      host.hardware.osKernel,
    ], separator: ' ');
    final iface = _primaryInterface(host);
    final throughput = host.metrics.netThroughputGbps;
    final capacity = host.metrics.netCapacityGbps;
    final memUsed = host.memoryUsedBytes;
    final memTotal = host.memoryTotalBytes;
    final memLabel = (memUsed != null && memTotal != null)
        ? '${_formatBytes(memUsed)} / ${_formatBytes(memTotal)}'
        : '${host.metrics.memoryUsedPercent.toStringAsFixed(1)}%';

    final stats = [
      _VitalStat(
        icon: Icons.speed,
        label: 'CPU',
        value: '${host.metrics.cpuLoad.toStringAsFixed(1)}%',
      ),
      _VitalStat(icon: Icons.memory, label: '메모리', value: memLabel),
      _VitalStat(
        icon: Icons.thermostat,
        label: '온도',
        value: host.cpuTemperature != null || host.gpuTemperature != null
            ? '${(host.cpuTemperature ?? host.gpuTemperature)!.toStringAsFixed(1)}℃'
            : 'N/A',
      ),
      _VitalStat(
        icon: Icons.wifi_tethering,
        label: '대역폭',
        value: throughput != null
            ? capacity != null
                  ? '${throughput.toStringAsFixed(2)} / ${capacity.toStringAsFixed(1)} Gbps'
                  : '${throughput.toStringAsFixed(2)} Gbps'
            : '계측 없음',
      ),
      _VitalStat(
        icon: Icons.access_time,
        label: '업타임',
        value: _formatDuration(host.uptime),
      ),
      _VitalStat(
        icon: Icons.device_hub,
        label: '인터페이스',
        value: iface?.speedLabel ?? host.ip,
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xE6050B16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x221B2333)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 18,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      host.ip,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (host.isDummy)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.amberAccent),
                    color: Colors.black26,
                  ),
                  child: const Text(
                    'DUMMY',
                    style: TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            osLabel,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          const SizedBox(height: 2),
          Text(
            'Agent ${host.agentVersion}',
            style: const TextStyle(color: Colors.white30, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: stats
                .map(
                  (stat) => _VitalStatTile(
                    icon: stat.icon,
                    label: stat.label,
                    value: stat.value,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SelectedTelemetryPanel extends StatelessWidget {
  const _SelectedTelemetryPanel({required this.host});

  final TwinHost host;

  @override
  Widget build(BuildContext context) {
    final temp = host.cpuTemperature ?? host.gpuTemperature;
    final capacity = host.metrics.netCapacityGbps;
    final throughput = host.metrics.netThroughputGbps ?? 0;
    final memCaption =
        host.memoryTotalBytes != null && host.memoryUsedBytes != null
        ? '${_formatBytes(host.memoryUsedBytes)} / ${_formatBytes(host.memoryTotalBytes)}'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricProgressRow(
          icon: Icons.speed,
          label: 'CPU 사용률',
          value: '${host.metrics.cpuLoad.toStringAsFixed(1)}%',
          progress: host.metrics.cpuLoad / 100,
          caption: '실시간',
        ),
        const SizedBox(height: 12),
        _MetricProgressRow(
          icon: Icons.memory,
          label: '메모리 사용률',
          value: '${host.metrics.memoryUsedPercent.toStringAsFixed(1)}%',
          progress: host.metrics.memoryUsedPercent / 100,
          caption: memCaption,
        ),
        const SizedBox(height: 12),
        _MetricProgressRow(
          icon: Icons.thermostat,
          label: '온도',
          value: temp != null ? '${temp.toStringAsFixed(1)}℃' : '센서 없음',
          progress: temp != null ? (temp / 110).clamp(0.0, 1.0) : null,
          caption: temp != null ? '센서 실측' : null,
        ),
        const SizedBox(height: 12),
        _MetricProgressRow(
          icon: Icons.network_check,
          label: '네트워크',
          value: capacity != null
              ? '${throughput.toStringAsFixed(2)} / ${capacity.toStringAsFixed(1)} Gbps'
              : '${throughput.toStringAsFixed(2)} Gbps',
          progress: capacity != null && capacity > 0
              ? (throughput / capacity).clamp(0.0, 1.0)
              : null,
          caption: capacity != null ? '링크 용량' : '용량 정보 없음',
        ),
      ],
    );
  }
}

class _VitalStat {
  const _VitalStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _VitalStatTile extends StatelessWidget {
  const _VitalStatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x11091A29),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x221B2333)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white54, size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlayHeader extends StatelessWidget {
  const _OverlayHeader({required this.host, required this.theme});

  final TwinHost host;
  final TextTheme theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                host.displayName,
                style: theme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                host.ip,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoPill(
              icon: host.isDummy
                  ? Icons.science_outlined
                  : Icons.shield_outlined,
              label: host.isDummy ? '더미 노드' : '실측 노드',
            ),
            if (host.rack != null)
              _InfoPill(icon: Icons.storage_rounded, label: host.rack!),
          ],
        ),
      ],
    );
  }
}

class _SystemSummaryPanel extends StatelessWidget {
  const _SystemSummaryPanel({required this.host});

  final TwinHost host;

  @override
  Widget build(BuildContext context) {
    final metrics = host.metrics;

    Iterable<(String, String)> buildRows() sync* {
      yield ('상태', host.status.name.toUpperCase());
      yield ('OS', host.osDisplay);
      yield (
        '하드웨어',
        _joinNonEmpty([
          host.hardware.systemManufacturer,
          host.hardware.systemModel,
        ]),
      );
      yield ('IP', host.ip);
      yield ('업타임', _formatDuration(host.uptime));
      yield ('CPU', host.cpuSummary);
      yield (
        '메모리',
        metrics.memoryTotalBytes != null && metrics.memoryAvailableBytes != null
            ? '${_formatBytes(metrics.memoryUsedBytes)} / ${_formatBytes(metrics.memoryTotalBytes)}'
            : '${metrics.memoryUsedPercent.toStringAsFixed(1)}%',
      );
      if (metrics.netThroughputGbps != null) {
        yield (
          '네트워크',
          metrics.netCapacityGbps != null
              ? '${metrics.netThroughputGbps!.toStringAsFixed(2)} / ${metrics.netCapacityGbps!.toStringAsFixed(2)} Gbps'
              : '${metrics.netThroughputGbps!.toStringAsFixed(2)} Gbps',
        );
      }
      if (metrics.swapUsedPercent != null) {
        yield ('스왑', '${metrics.swapUsedPercent!.toStringAsFixed(1)}%');
      }
      yield ('에이전트', host.agentVersion);
      yield ('마지막 수신', host.lastSeen.toLocal().toIso8601String());
    }

    final rows = buildRows().toList();

    return _GlassTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '시스템 상태',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 12,
              childAspectRatio: 3.6,
            ),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final entry = rows[index];
              return _SystemStatCell(label: entry.$1, value: entry.$2);
            },
          ),
        ],
      ),
    );
  }
}

class _SystemStatCell extends StatelessWidget {
  const _SystemStatCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ProcessPanel extends StatelessWidget {
  const _ProcessPanel({required this.host});

  final TwinHost host;

  @override
  Widget build(BuildContext context) {
    final processes = host.diagnostics.topProcesses
        .take(4)
        .toList(growable: false);
    return _GlassTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '상위 프로세스',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (processes.isEmpty)
            const Text(
              '데이터 없음',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            )
          else
            ...processes.map((process) => _ProcessRow(process: process)),
        ],
      ),
    );
  }
}

class _InterfacePanel extends StatelessWidget {
  const _InterfacePanel({required this.host});

  final TwinHost host;

  @override
  Widget build(BuildContext context) {
    final interfaces = host.diagnostics.interfaces
        .take(3)
        .toList(growable: false);
    return _GlassTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '네트워크 인터페이스',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (interfaces.isEmpty)
            const Text(
              '데이터 없음',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            )
          else
            _InterfaceBadgeBar(interfaces: interfaces),
        ],
      ),
    );
  }
}

class _StoragePanel extends StatelessWidget {
  const _StoragePanel({required this.host});

  final TwinHost host;

  @override
  Widget build(BuildContext context) {
    final disks = host.diagnostics.disks.take(3).toList(growable: false);
    return _GlassTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '스토리지',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (disks.isEmpty)
            const Text(
              '데이터 없음',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            )
          else
            ...disks.map((disk) => _DiskUsageBar(disk: disk)),
        ],
      ),
    );
  }
}

class _GlassTile extends StatelessWidget {
  const _GlassTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x110C1A2A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x221B2333)),
      ),
      padding: const EdgeInsets.all(14),
      child: child,
    );
  }
}

class _InfoWidgetConfig {
  const _InfoWidgetConfig({required this.title, required this.child});

  final String title;
  final Widget child;
}

class _TrendTile extends StatelessWidget {
  const _TrendTile({required this.value, this.caption, required this.trend});

  final String value;
  final String? caption;
  final double trend;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              caption!,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
        const SizedBox(height: 8),
        _TrendBar(percent: trend),
      ],
    );
  }
}

class _TrendBar extends StatelessWidget {
  const _TrendBar({required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: (percent / 100).clamp(0.0, 1.0),
        minHeight: 6,
        backgroundColor: const Color(0xFF111B2B),
        valueColor: AlwaysStoppedAnimation<Color>(
          Colors.tealAccent.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

class _ProcessRow extends StatelessWidget {
  const _ProcessRow({required this.process});

  final TwinProcessSample process;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  process.name,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                if (process.username != null)
                  Text(
                    process.username!,
                    style: const TextStyle(color: Colors.white24, fontSize: 10),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 90,
            child: LinearProgressIndicator(
              value: (process.cpuPercent / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: const Color(0xFF1B2333),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Colors.tealAccent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${process.cpuPercent.toStringAsFixed(1)}%',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DiskUsageBar extends StatelessWidget {
  const _DiskUsageBar({required this.disk});

  final TwinDiskUsage disk;

  double? get _usagePercent {
    if (disk.usedPercent != null) {
      return disk.usedPercent!.clamp(0, 100);
    }
    if (disk.usedBytes != null &&
        disk.totalBytes != null &&
        disk.totalBytes! > 0) {
      return (disk.usedBytes! / disk.totalBytes!) * 100;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final usagePercent = _usagePercent;
    final usageText = (disk.usedBytes != null && disk.totalBytes != null)
        ? '${_formatBytes(disk.usedBytes)} / ${_formatBytes(disk.totalBytes)}'
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${disk.device} · ${disk.mountpoint}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: usagePercent != null
                  ? (usagePercent / 100).clamp(0.0, 1.0)
                  : 0,
              minHeight: 6,
              backgroundColor: const Color(0xFF101826),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Colors.deepOrangeAccent,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            usagePercent != null
                ? '${usagePercent.toStringAsFixed(1)}% 사용${usageText != null ? ' · $usageText' : ''}'
                : (usageText ?? '사용량 N/A'),
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _InterfaceBadgeBar extends StatelessWidget {
  const _InterfaceBadgeBar({required this.interfaces});

  final List<TwinInterfaceStats> interfaces;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: interfaces
          .map(
            (iface) => _InfoPill(
              icon: iface.isUp == false ? Icons.link_off : Icons.link,
              label: iface.speedLabel,
            ),
          )
          .toList(growable: false),
    );
  }
}

TwinInterfaceStats? _primaryInterface(TwinHost host) {
  for (final iface in host.diagnostics.interfaces) {
    if (iface.isUp != false) {
      return iface;
    }
  }
  return host.diagnostics.interfaces.isNotEmpty
      ? host.diagnostics.interfaces.first
      : null;
}

String _formatInterfaceDescriptor(TwinHost host, bool isSource) {
  final iface = _primaryInterface(host);
  final name = iface?.name ?? (isSource ? 'SOURCE' : 'TARGET');
  final speed = _formatInterfaceSpeed(iface);
  return '${host.displayName} / $name · $speed';
}

String _formatInterfaceSpeed(TwinInterfaceStats? iface) {
  final speed = iface?.speedMbps;
  if (speed == null || !speed.isFinite || speed <= 0) {
    return 'N/A';
  }
  if (speed >= 1000) {
    return '${(speed / 1000).toStringAsFixed(1)} Gbps';
  }
  return '${speed.toStringAsFixed(0)} Mbps';
}

class _HostChipRail extends StatelessWidget {
  const _HostChipRail({
    required this.hosts,
    required this.selectedHost,
    required this.onSelect,
  });

  final List<TwinHost> hosts;
  final String? selectedHost;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final visible = hosts.where((host) => !host.isCore).toList();
    if (visible.isEmpty) {
      return const SizedBox.shrink();
    }

    return AnimatedSlide(
      offset: Offset.zero,
      duration: const Duration(milliseconds: 280),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xF0050A14),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x221B2333)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 24,
              offset: Offset(0, 20),
            ),
          ],
        ),
        child: SizedBox(
          height: 78,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, index) {
              final host = visible[index];
              return _HostChip(
                host: host,
                isSelected: host.hostname == selectedHost,
                onTap: () => onSelect(host.hostname),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemCount: visible.length,
          ),
        ),
      ),
    );
  }
}

class _HostChip extends StatelessWidget {
  const _HostChip({
    required this.host,
    required this.isSelected,
    required this.onTap,
  });

  final TwinHost host;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (host.status) {
      TwinHostStatus.online => Colors.tealAccent,
      TwinHostStatus.stale => Colors.amberAccent,
      TwinHostStatus.offline => Colors.redAccent,
    };

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 180,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF123049) : const Color(0xFF070C16),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? Colors.tealAccent.withValues(alpha: 0.5)
                : const Color(0x221B2333),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    host.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (host.isDummy)
                  const Icon(
                    Icons.science_outlined,
                    size: 14,
                    color: Colors.amberAccent,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'CPU ${host.metrics.cpuLoad.toStringAsFixed(1)}% · RAM ${host.metrics.memoryUsedPercent.toStringAsFixed(1)}%',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
            if (host.metrics.netThroughputGbps != null)
              Text(
                '${host.metrics.netThroughputGbps!.toStringAsFixed(2)} Gbps',
                style: const TextStyle(color: Colors.tealAccent, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}

class _RealtimeTelemetryCard extends StatelessWidget {
  const _RealtimeTelemetryCard({required this.host, required this.samples});

  final TwinHost host;
  final List<_MetricSample> samples;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = samples.isNotEmpty ? samples.last : null;
    final throughput =
        host.metrics.netThroughputGbps ?? latest?.throughput ?? 0;
    final capacity = host.metrics.netCapacityGbps;
    final temperature =
        host.cpuTemperature ?? host.gpuTemperature ?? latest?.temperature;
    final uptimeText = _formatDuration(host.uptime);
    final memorySubtitle =
        host.memoryUsedBytes != null && host.memoryTotalBytes != null
        ? '${_formatBytes(host.memoryUsedBytes)} / ${_formatBytes(host.memoryTotalBytes)}'
        : '${host.metrics.memoryUsedPercent.toStringAsFixed(1)}%';

    const gaugeSize = 130.0;
    const padding = EdgeInsets.all(18);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF050B15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1B2333)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '실시간 텔레메트리',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _AnalogGauge(
                  label: 'CPU',
                  value: host.metrics.cpuLoad.clamp(0, 100).toDouble(),
                  maxValue: 100,
                  units: '%',
                  decimals: 1,
                  subtitle: '업타임 $uptimeText',
                  startColor: Colors.lightBlueAccent,
                  endColor: Colors.deepOrangeAccent,
                  size: gaugeSize,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AnalogGauge(
                  label: '메모리',
                  value: host.metrics.memoryUsedPercent
                      .clamp(0, 100)
                      .toDouble(),
                  maxValue: 100,
                  units: '%',
                  decimals: 1,
                  subtitle: memorySubtitle,
                  startColor: const Color(0xFF7C3AED),
                  endColor: Colors.pinkAccent,
                  size: gaugeSize,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MetricProgressRow(
            icon: Icons.device_thermostat,
            label: '온도',
            value: temperature != null
                ? '${temperature.toStringAsFixed(1)}℃'
                : 'N/A',
            progress: temperature != null
                ? (temperature / 110).clamp(0.0, 1.0)
                : null,
            caption: temperature != null ? '센서 실측' : '센서 데이터 없음',
          ),
          const SizedBox(height: 12),
          _MetricProgressRow(
            icon: Icons.network_check,
            label: '네트워크',
            value: throughput > 0
                ? '${throughput.toStringAsFixed(2)} Gbps'
                : 'N/A',
            progress: capacity != null && capacity > 0
                ? (throughput / capacity).clamp(0.0, 1.0)
                : null,
            caption: capacity != null
                ? '용량 ${capacity.toStringAsFixed(2)} Gbps'
                : '용량 정보 없음',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SparklineChart(
                  label: 'CPU 히스토리',
                  unit: '%',
                  color: Colors.tealAccent,
                  samples: samples,
                  selector: (sample) => sample.cpu,
                  precision: 1,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SparklineChart(
                  label: '스루풋',
                  unit: 'Gbps',
                  color: Colors.deepOrangeAccent,
                  samples: samples,
                  selector: (sample) => sample.throughput,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricProgressRow extends StatelessWidget {
  const _MetricProgressRow({
    required this.icon,
    required this.label,
    required this.value,
    this.progress,
    this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final double? progress;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.white54),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (progress != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: const Color(0xFF101826),
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.tealAccent.withValues(alpha: 0.75),
                ),
              ),
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
    );
  }
}

class _SparklineChart extends StatelessWidget {
  const _SparklineChart({
    required this.label,
    required this.unit,
    required this.color,
    required this.samples,
    required this.selector,
    this.precision = 2,
  });

  final String label;
  final String unit;
  final Color color;
  final List<_MetricSample> samples;
  final double? Function(_MetricSample sample) selector;
  final int precision;

  @override
  Widget build(BuildContext context) {
    final current = samples.isNotEmpty ? selector(samples.last) : null;
    final valueText = current != null && current.isFinite
        ? '${current.toStringAsFixed(precision)} $unit'
        : 'N/A';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF080F1C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF111B2B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            valueText,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 60,
            child: CustomPaint(
              painter: _SparklinePainter(
                samples: samples,
                selector: selector,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.samples,
    required this.selector,
    required this.color,
  });

  final List<_MetricSample> samples;
  final double? Function(_MetricSample sample) selector;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) {
      _drawBaseline(canvas, size);
      return;
    }

    final values = <double>[];
    for (final sample in samples) {
      final value = selector(sample);
      if (value != null && value.isFinite) {
        values.add(value);
      }
    }
    if (values.isEmpty) {
      _drawBaseline(canvas, size);
      return;
    }

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = (maxValue - minValue).abs() < 0.001
        ? (maxValue == 0 ? 1 : maxValue.abs())
        : (maxValue - minValue);

    final points = <Offset>[];
    final total = samples.length;
    for (var i = 0; i < total; i++) {
      final value = selector(samples[i]);
      if (value == null || !value.isFinite) continue;
      final normalized = ((value - minValue) / range).clamp(0.0, 1.0);
      final x = total == 1 ? 0.0 : (i / (total - 1)) * size.width;
      final y = size.height - (normalized * size.height);
      points.add(Offset(x, y));
    }

    if (points.length < 2) {
      _drawBaseline(canvas, size);
      return;
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..isAntiAlias = true;
    canvas.drawPath(path, stroke);

    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [color.withValues(alpha: 0.35), Colors.transparent],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);
  }

  void _drawBaseline(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(0, size.height - 2),
      Offset(size.width, size.height - 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => true;
}

class _MetricHistoryBuffer {
  _MetricHistoryBuffer();

  static const int _capacity = 240;
  final List<_MetricSample> _samples = [];

  List<_MetricSample> get samples => List.unmodifiable(_samples);
  _MetricSample? get latest => _samples.isNotEmpty ? _samples.last : null;

  void add(_MetricSample sample) {
    _samples.add(sample);
    if (_samples.length > _capacity) {
      _samples.removeRange(0, _samples.length - _capacity);
    }
  }

  void clear() => _samples.clear();
}

class _MetricSample {
  const _MetricSample({
    required this.timestamp,
    required this.cpu,
    required this.memory,
    this.throughput,
    this.temperature,
  });

  final DateTime timestamp;
  final double cpu;
  final double memory;
  final double? throughput;
  final double? temperature;
}

class _TwinScenePainter extends CustomPainter {
  _TwinScenePainter(
    this.frame, {
    required this.mode,
    required this.selectedHost,
    required this.heatMax,
    required this.cameraFocus,
    required this.linkPulse,
  });

  final TwinStateFrame frame;
  final TwinViewportMode mode;
  final String? selectedHost;
  final double heatMax;
  final TwinPosition cameraFocus;
  final double linkPulse;

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
      ..shader =
          const RadialGradient(
            colors: [Color(0xFF0B2234), Colors.transparent],
            radius: 0.8,
          ).createShader(
            Rect.fromCircle(
              center: size.center(Offset.zero),
              radius: size.shortestSide * 0.55,
            ),
          );
    canvas.drawCircle(
      size.center(Offset.zero),
      size.shortestSide * 0.55,
      haloPaint,
    );
  }

  void _paintLinks(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final scale = twinScaleFactor(frame, size);
    final hosts = {for (final host in frame.hosts) host.hostname: host};

    for (final link in frame.links) {
      final source = hosts[link.source];
      final target = hosts[link.target];
      if (source == null || target == null) continue;

      final sourcePoint = twinProjectPoint(
        source.position,
        center,
        scale,
        cameraFocus,
      );
      final targetPoint = twinProjectPoint(
        target.position,
        center,
        scale,
        cameraFocus,
      );

      final controlPoint = Offset(
        (sourcePoint.dx + targetPoint.dx) / 2,
        math.min(sourcePoint.dy, targetPoint.dy) - 40,
      );

      final capacity = link.capacityGbps ?? 0;
      final measured = link.throughputGbps;
      final utilization = capacity > 0
          ? (measured / capacity).clamp(0.0, 1.0)
          : link.utilization.clamp(0.0, 1.0);
      final pulse = 0.25 + 0.75 * linkPulse;
      final color = Color.lerp(
        Colors.tealAccent,
        Colors.deepOrangeAccent,
        utilization,
      )!;

      final path = Path()
        ..moveTo(sourcePoint.dx, sourcePoint.dy)
        ..quadraticBezierTo(
          controlPoint.dx,
          controlPoint.dy,
          targetPoint.dx,
          targetPoint.dy,
        );

      final baseGlow = Paint()
        ..color = color.withValues(alpha: 0.09)
        ..strokeWidth = 10 + utilization * 6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 12);
      canvas.drawPath(path, baseGlow);

      final paint = Paint()
        ..shader = ui.Gradient.linear(sourcePoint, targetPoint, [
          color.withValues(alpha: 0.2),
          color.withValues(alpha: 0.95),
        ])
        ..strokeWidth = 2 + utilization * 4 + pulse
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(path, paint);

      final metrics = path.computeMetrics();
      for (final metric in metrics) {
        final window = (46 + utilization * 70).clamp(24.0, metric.length * 0.8);
        final offset = (metric.length - window) * (0.1 + linkPulse * 0.8);
        final highlight = metric.extractPath(
          offset,
          math.min(metric.length, offset + window),
        );
        final highlightPaint = Paint()
          ..shader = ui.Gradient.linear(
            highlight.getBounds().topLeft,
            highlight.getBounds().bottomRight,
            [
              Colors.white.withValues(alpha: 0.12),
              Colors.white.withValues(alpha: 0.85),
            ],
          )
          ..strokeWidth = paint.strokeWidth + 1.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        canvas.drawPath(highlight, highlightPaint);
      }

      final midPoint = _quadraticPoint(
        sourcePoint,
        controlPoint,
        targetPoint,
        0.5,
      );
      final sourceDescriptor = _formatInterfaceDescriptor(source, true);
      final targetDescriptor = _formatInterfaceDescriptor(target, false);
      final bandwidthLabel = capacity > 0
          ? '${measured.toStringAsFixed(2)} / ${capacity.toStringAsFixed(1)} Gbps'
          : '${measured.toStringAsFixed(2)} Gbps';
      final utilizationLabel =
          '${(utilization * 100).clamp(0, 100).toStringAsFixed(0)}% 사용';
      final linkLabel = TextPainter(
        text: TextSpan(
          text:
              '$sourceDescriptor → $targetDescriptor\n$bandwidthLabel · $utilizationLabel',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: 320);

      linkLabel.paint(canvas, midPoint + const Offset(-62, -30));
    }
  }

  void _paintHosts(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final scale = twinScaleFactor(frame, size);

    for (final host in frame.hosts) {
      final position = twinProjectPoint(
        host.position,
        center,
        scale,
        cameraFocus,
      );
      final status = host.status;
      final isCore = host.isCore;
      final isSelected = selectedHost != null && selectedHost == host.hostname;

      Color color;
      if (mode == TwinViewportMode.heatmap) {
        final heatValue =
            host.cpuTemperature ?? host.gpuTemperature ?? host.metrics.cpuLoad;
        final normalized = heatMax > 0
            ? (heatValue / heatMax).clamp(0.0, 1.0)
            : 0.0;
        color =
            Color.lerp(
              const Color(0xFF38BDF8),
              Colors.deepOrangeAccent,
              normalized,
            ) ??
            Colors.tealAccent;
        if (status == TwinHostStatus.offline) {
          color = Colors.grey.shade700;
        }
      } else {
        color = switch (status) {
          TwinHostStatus.online => Colors.tealAccent,
          TwinHostStatus.stale => Colors.amberAccent,
          TwinHostStatus.offline => Colors.redAccent,
        };
      }

      final radius = hostBubbleRadius(host);

      final nodePaint = Paint()
        ..color = color.withValues(alpha: isCore ? 0.9 : 0.75)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(position, radius, nodePaint);

      if (isSelected) {
        canvas.drawCircle(
          position,
          radius + 10,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2,
        );
      } else if (!isCore) {
        canvas.drawCircle(
          position,
          radius + 6,
          Paint()
            ..color = color.withValues(alpha: 0.18)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }

      if (host.isDummy && !isCore) {
        final markerPath = Path()
          ..moveTo(position.dx, position.dy - radius - 4)
          ..lineTo(position.dx + 8, position.dy - radius - 16)
          ..lineTo(position.dx - 8, position.dy - radius - 16)
          ..close();
        canvas.drawPath(
          markerPath,
          Paint()
            ..color = Colors.amberAccent.withValues(alpha: 0.8)
            ..style = PaintingStyle.fill,
        );
      }

      final labelText = host.isDummy
          ? '${host.displayLabel}\n(더미)'
          : host.displayLabel;
      final textPainter = TextPainter(
        text: TextSpan(
          text: labelText,
          style: TextStyle(
            color: Colors.white.withValues(alpha: isSelected ? 1 : 0.85),
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

      final infoPainter = TextPainter(
        text: TextSpan(
          text:
              'CPU ${host.metrics.cpuLoad.toStringAsFixed(0)}% · RAM ${host.metrics.memoryUsedPercent.toStringAsFixed(0)}%',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 10,
            fontWeight: FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 180);

      infoPainter.paint(
        canvas,
        position + Offset(-infoPainter.width / 2, radius + 24),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TwinScenePainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.mode != mode ||
      oldDelegate.selectedHost != selectedHost ||
      oldDelegate.heatMax != heatMax ||
      oldDelegate.cameraFocus != cameraFocus ||
      oldDelegate.linkPulse != linkPulse;
}

double twinScaleFactor(TwinStateFrame frame, Size size) {
  final radius = frame.maxRadius;
  if (radius <= 0) return 1;
  const margin = 64.0;
  final shortest = size.shortestSide;
  if (!shortest.isFinite || shortest <= margin * 2) {
    return 1;
  }
  return ((shortest / 2) - margin) / radius;
}

Offset twinProjectPoint(
  TwinPosition position,
  Offset center,
  double scale, [
  TwinPosition focus = TwinPosition.zero,
]) {
  final adjusted = position.subtract(focus);
  final x = center.dx + adjusted.x * scale;
  final y = center.dy + adjusted.z * scale - adjusted.y * 0.8;
  return Offset(x, y);
}

Offset _quadraticPoint(Offset p0, Offset p1, Offset p2, double t) {
  final omt = 1 - t;
  final x = omt * omt * p0.dx + 2 * omt * t * p1.dx + t * t * p2.dx;
  final y = omt * omt * p0.dy + 2 * omt * t * p1.dy + t * t * p2.dy;
  return Offset(x, y);
}

double hostBubbleRadius(TwinHost host) {
  if (host.isCore) {
    return 22.0;
  }
  final cpuLoad = host.metrics.cpuLoad.clamp(0.0, 100.0);
  return 10.0 + cpuLoad * 0.06;
}

String _formatBytes(double? bytes) {
  if (bytes == null || bytes.isNaN) {
    return 'N/A';
  }
  const kilo = 1024;
  const mega = kilo * 1024;
  const giga = mega * 1024;
  if (bytes >= giga) {
    return '${(bytes / giga).toStringAsFixed(1)} GB';
  }
  if (bytes >= mega) {
    return '${(bytes / mega).toStringAsFixed(1)} MB';
  }
  if (bytes >= kilo) {
    return '${(bytes / kilo).toStringAsFixed(1)} KB';
  }
  return '${bytes.toStringAsFixed(0)} B';
}

String _formatDuration(Duration duration) {
  final days = duration.inDays;
  final hours = duration.inHours % 24;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  final parts = <String>[];
  if (days > 0) parts.add('${days}d');
  if (hours > 0) parts.add('${hours}h');
  if (minutes > 0) parts.add('${minutes}m');
  if (parts.isEmpty) {
    parts.add('${seconds}s');
  }
  return parts.join(' ');
}

String _joinNonEmpty(List<String?> values, {String separator = ' · '}) {
  final filtered = values
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
  if (filtered.isEmpty) {
    return 'N/A';
  }
  return filtered.join(separator);
}
