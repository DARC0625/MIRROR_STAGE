import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'core/models/command_models.dart';
import 'core/models/twin_models.dart';
import 'core/services/command_service.dart';
import 'core/services/twin_channel.dart';

enum TwinViewportMode { topology, heatmap }

enum SidebarWing { left, right }

enum SidebarWidgetType {
  globalMetrics,
  globalLink,
  globalTemperature,
  commandConsole,
  telemetry,
  hostLink,
  hostTemperature,
  processes,
  network,
  storage,
}

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
  final TwinViewportMode _viewportMode = TwinViewportMode.topology;
  String? _selectedHostName;
  late final _WidgetDockController _dockController;
  bool _showWidgetPalette = false;

  @override
  void initState() {
    super.initState();
    _ownsChannel = widget.channel == null;
    _channel = widget.channel ?? TwinChannel();
    _stream = _channel.stream();
    _dockController = _WidgetDockController(
      initialPlacements: _defaultDockPlacements,
    );
  }

  @override
  void dispose() {
    if (_ownsChannel) {
      _channel.dispose();
    }
    _dockController.dispose();
    super.dispose();
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
          body: Stack(
            children: [
              SafeArea(
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
                      selectedHost: selectedHost,
                      controller: _dockController,
                      wing: SidebarWing.left,
                      paletteOpen: _showWidgetPalette,
                      onTogglePalette: _togglePalette,
                    );
                    final rightPanel = _StatusSidebar(
                      frame: frame,
                      selectedHost: selectedHost,
                      controller: _dockController,
                    );

                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 360, child: leftPanel),
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
                          height: (constraints.maxHeight * 0.4).clamp(
                            280.0,
                            460.0,
                          ),
                          child: rightPanel,
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (_showWidgetPalette)
                _WidgetPaletteOverlay(
                  controller: _dockController,
                  onClose: _togglePalette,
                ),
            ],
          ),
        );
      },
    );
  }

  void _togglePalette() {
    setState(() => _showWidgetPalette = !_showWidgetPalette);
  }

  void _clearSelection() {
    if (_selectedHostName != null) {
      setState(() => _selectedHostName = null);
    }
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.frame,
    required this.selectedHost,
    required this.controller,
    required this.wing,
    required this.paletteOpen,
    required this.onTogglePalette,
  });

  final TwinStateFrame frame;
  final TwinHost? selectedHost;
  final _WidgetDockController controller;
  final SidebarWing wing;
  final bool paletteOpen;
  final VoidCallback onTogglePalette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
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
                'MIRROR STAGE',
                style: theme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
              _WidgetPaletteButton(
                isActive: paletteOpen,
                onPressed: onTogglePalette,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Flexible(
            fit: FlexFit.loose,
            child: _WidgetGridPanel(
              wing: wing,
              controller: controller,
              frame: frame,
              selectedHost: selectedHost,
              samples: const <_MetricSample>[],
              emptyLabel: '위젯 패널에서 원하는 모듈을 배치하세요.',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusSidebar extends StatefulWidget {
  const _StatusSidebar({
    required this.frame,
    required this.selectedHost,
    required this.controller,
  });

  final TwinStateFrame frame;
  final TwinHost? selectedHost;
  final _WidgetDockController controller;

  @override
  State<_StatusSidebar> createState() => _StatusSidebarState();
}

class _StatusSidebarState extends State<_StatusSidebar> {
  final Map<String, _MetricHistoryBuffer> _historyByHost = {};
  final Map<String, DateTime> _lastTimestampByHost = {};

  @override
  void initState() {
    super.initState();
    _ingestSample();
  }

  @override
  void didUpdateWidget(covariant _StatusSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ingestSample();
  }

  void _ingestSample() {
    final host = widget.selectedHost;
    if (host == null) return;

    final timestamp = widget.frame.generatedAt;
    final key = host.hostname;
    final last = _lastTimestampByHost[key];
    if (last != null && !timestamp.isAfter(last)) {
      return;
    }

    final buffer = _historyByHost.putIfAbsent(key, _MetricHistoryBuffer.new);
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
    _lastTimestampByHost[key] = timestamp;
  }

  @override
  Widget build(BuildContext context) {
    final samples = widget.selectedHost != null
        ? _historyByHost[widget.selectedHost!.hostname]?.samples ??
              const <_MetricSample>[]
        : const <_MetricSample>[];

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
      child: _WidgetGridPanel(
        wing: SidebarWing.right,
        controller: widget.controller,
        frame: widget.frame,
        selectedHost: widget.selectedHost,
        samples: samples,
        emptyLabel: widget.selectedHost == null
            ? '노드를 선택하면 텔레메트리를 띄울 수 있습니다.'
            : '위젯을 배치하여 정보를 구성하세요.',
      ),
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
  late final Listenable _stageTicker;
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
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _linkPulseAnimation = CurvedAnimation(
      parent: _linkPulseController,
      curve: Curves.easeInOutSine,
    );
    _stageTicker = Listenable.merge([_cameraController, _linkPulseController]);
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
          animation: _stageTicker,
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

class _SidebarOverviewCard extends StatelessWidget {
  const _SidebarOverviewCard({required this.frame});

  final TwinStateFrame frame;

  @override
  Widget build(BuildContext context) {
    final avgCpu = frame.averageCpuLoad.clamp(0, 100).toDouble();
    final memUtil = frame.memoryUtilizationPercent.clamp(0, 100).toDouble();
    final memCaption = frame.totalMemoryCapacityGb > 0
        ? '${frame.totalMemoryUsedGb.toStringAsFixed(1)}/${frame.totalMemoryCapacityGb.toStringAsFixed(1)} GB'
        : null;

    return _GlassTile(
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
          Row(
            children: [
              Expanded(
                child: _AnalogGauge(
                  label: '평균 CPU',
                  value: avgCpu,
                  maxValue: 100,
                  units: '%',
                  decimals: 1,
                  subtitle: frame.averageCpuTemperature > 0
                      ? '온도 ${frame.averageCpuTemperature.toStringAsFixed(1)}℃'
                      : null,
                  startColor: Colors.lightBlueAccent,
                  endColor: Colors.deepOrangeAccent,
                  size: 110,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AnalogGauge(
                  label: '메모리 사용률',
                  value: memUtil,
                  maxValue: 100,
                  units: '%',
                  decimals: 1,
                  subtitle: memCaption,
                  startColor: const Color(0xFF38BDF8),
                  endColor: Colors.pinkAccent,
                  size: 110,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommandConsoleCard extends StatefulWidget {
  const _CommandConsoleCard({required this.frame, required this.selectedHost});

  final TwinStateFrame frame;
  final TwinHost? selectedHost;

  @override
  State<_CommandConsoleCard> createState() => _CommandConsoleCardState();
}

class _CommandConsoleCardState extends State<_CommandConsoleCard> {
  late final CommandService _commandService;
  final TextEditingController _commandController = TextEditingController();
  final TextEditingController _timeoutController = TextEditingController();
  final List<CommandJob> _jobs = [];
  String? _selectedHostname;
  String? _formError;
  bool _sending = false;
  bool _loading = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _commandService = CommandService();
    _selectedHostname = widget.selectedHost?.hostname ?? _firstHostName();
    _refreshCommands();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshCommands(),
    );
  }

  @override
  void didUpdateWidget(covariant _CommandConsoleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedHostname == null && widget.selectedHost != null) {
      setState(() => _selectedHostname = widget.selectedHost!.hostname);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _commandService.dispose();
    _commandController.dispose();
    _timeoutController.dispose();
    super.dispose();
  }

  String? _firstHostName() {
    for (final host in widget.frame.hosts) {
      if (!host.isCore) {
        return host.hostname;
      }
    }
    return null;
  }

  Future<void> _refreshCommands() async {
    if (_loading) return;
    if (_selectedHostname == null) return;
    setState(() => _loading = true);
    try {
      final result = await _commandService.listCommands(
        hostname: _selectedHostname,
        page: 1,
        pageSize: 5,
      );
      if (!mounted) return;
      setState(() {
        _jobs
          ..clear()
          ..addAll(result.items);
      });
    } catch (_) {
      // ignore
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submitCommand() async {
    final target = _selectedHostname;
    if (target == null) {
      setState(() => _formError = '대상 노드를 선택하세요.');
      return;
    }
    final command = _commandController.text.trim();
    if (command.isEmpty) {
      setState(() => _formError = '명령을 입력하세요.');
      return;
    }
    double? timeout;
    if (_timeoutController.text.trim().isNotEmpty) {
      timeout = double.tryParse(_timeoutController.text.trim());
    }
    setState(() {
      _formError = null;
      _sending = true;
    });
    try {
      await _commandService.createCommand(
        hostname: target,
        command: command,
        timeoutSeconds: timeout,
      );
      _commandController.clear();
      _timeoutController.clear();
      await _refreshCommands();
    } catch (error) {
      setState(() => _formError = '전송 실패: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Color _statusColor(CommandStatus status) {
    switch (status) {
      case CommandStatus.pending:
        return Colors.amberAccent;
      case CommandStatus.running:
        return Colors.lightBlueAccent;
      case CommandStatus.succeeded:
        return Colors.tealAccent;
      case CommandStatus.failed:
        return Colors.redAccent;
      case CommandStatus.timeout:
        return Colors.deepOrangeAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hosts = widget.frame.hosts.where((host) => !host.isCore).toList();
    final visibleJobs = _jobs.take(2).toList(growable: false);
    if (hosts.isEmpty) {
      return _GlassTile(
        child: SizedBox(
          height: 220,
          child: Center(
            child: Text(
              '제어 가능한 노드가 없습니다.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
        ),
      );
    }
    final hostItems = hosts
        .map(
          (host) => DropdownMenuItem<String>(
            value: host.hostname,
            child: Text(host.displayName),
          ),
        )
        .toList();

    return _GlassTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '원격 자동화',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: '대상 노드',
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedHostname ?? hostItems.first.value,
                items: hostItems,
                onChanged: (value) => setState(() => _selectedHostname = value),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _commandController,
            decoration: const InputDecoration(
              labelText: '명령어',
              hintText: '예) ipconfig /all',
              border: OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 2,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _timeoutController,
            decoration: const InputDecoration(
              labelText: '타임아웃(초, 선택)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _sending ? null : _submitCommand,
                icon: _sending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send, size: 16),
                label: const Text('실행'),
              ),
              const SizedBox(width: 12),
              if (_formError != null)
                Expanded(
                  child: Text(
                    _formError!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
          if (visibleJobs.isEmpty)
            const Text(
              '명령 기록이 없습니다.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            )
          else
            ...visibleJobs.map(
              (job) =>
                  _CommandJobTile(color: _statusColor(job.status), job: job),
            ),
        ],
      ),
    );
  }
}

class _CommandJobTile extends StatelessWidget {
  const _CommandJobTile({required this.color, required this.job});

  final Color color;
  final CommandJob job;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0x110A1018),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x221B2333)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job.command,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Chip(
                backgroundColor: color.withValues(alpha: 0.15),
                side: BorderSide.none,
                label: Text(
                  job.statusLabel,
                  style: TextStyle(color: color, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${job.hostname} · ${job.requestedLabel}',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
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

class _RealtimeTelemetryCard extends StatelessWidget {
  const _RealtimeTelemetryCard({required this.host, required this.samples});

  final TwinHost host;
  final List<_MetricSample> samples;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          const SizedBox(height: 12),
          Text(
            '업타임 $uptimeText',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
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
    final picture = _GridPictureCache.instance.pictureFor(size);
    canvas.drawPicture(picture);

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

      if (!(source.status == TwinHostStatus.online &&
          target.status == TwinHostStatus.online)) {
        final offlinePaint = Paint()
          ..color = Colors.redAccent.withValues(alpha: 0.6)
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        _drawDashedPath(canvas, path, offlinePaint);
        continue;
      }

      final slackPaint = Paint()
        ..color = Colors.tealAccent.withValues(alpha: (1 - utilization) * 0.12)
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, slackPaint);

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
        final forwardOffset =
            (metric.length - window) * (0.1 + linkPulse * 0.8);
        final highlight = metric.extractPath(
          forwardOffset,
          math.min(metric.length, forwardOffset + window),
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
          ..strokeWidth = paint.strokeWidth + 1.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        canvas.drawPath(highlight, highlightPaint);

        final reverseOffset =
            (metric.length - window) * (0.2 + (1 - linkPulse) * 0.7);
        final reverse = metric.extractPath(
          reverseOffset,
          math.min(metric.length, reverseOffset + window),
        );
        final reversePaint = Paint()
          ..shader = ui.Gradient.linear(
            reverse.getBounds().bottomRight,
            reverse.getBounds().topLeft,
            [
              Colors.white.withValues(alpha: 0.08),
              color.withValues(alpha: 0.8),
            ],
          )
          ..strokeWidth = paint.strokeWidth + 0.8
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        canvas.drawPath(reverse, reversePaint);

        final tangent = metric.getTangentForOffset(
          forwardOffset + window * 0.9,
        );
        if (tangent != null) {
          _drawArrowHead(
            canvas,
            tangent.position,
            tangent.vector.direction,
            color,
          );
        }
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

      final glowPaint = Paint()
        ..color = color.withValues(alpha: isSelected ? 0.45 : 0.25)
        ..style = PaintingStyle.fill
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 18);
      canvas.drawCircle(position, radius + (isSelected ? 16 : 12), glowPaint);

      final nodePaint = Paint()
        ..shader = ui.Gradient.radial(position, radius + 4, [
          Colors.white.withValues(alpha: 0.9),
          color.withValues(alpha: isCore ? 0.95 : 0.7),
        ])
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

      canvas.drawCircle(
        position,
        radius * 0.55,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );

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

void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
  const dash = 10.0;
  const gap = 6.0;
  for (final metric in path.computeMetrics()) {
    double distance = 0;
    while (distance < metric.length) {
      final next = math.min(metric.length, distance + dash);
      final segment = metric.extractPath(distance, next);
      canvas.drawPath(segment, paint);
      distance = next + gap;
    }
  }
}

void _drawArrowHead(
  Canvas canvas,
  Offset position,
  double direction,
  Color color,
) {
  const size = 8.0;
  final path = Path()
    ..moveTo(position.dx, position.dy)
    ..lineTo(
      position.dx - size * math.cos(direction - 0.4),
      position.dy - size * math.sin(direction - 0.4),
    )
    ..lineTo(
      position.dx - size * math.cos(direction + 0.4),
      position.dy - size * math.sin(direction + 0.4),
    )
    ..close();
  canvas.drawPath(
    path,
    Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill,
  );
}

class _GridPictureCache {
  _GridPictureCache._();
  static final _GridPictureCache instance = _GridPictureCache._();

  final Map<_GridCacheKey, ui.Picture> _cache = {};

  ui.Picture pictureFor(Size size) {
    final key = _GridCacheKey(size);
    final cached = _cache[key];
    if (cached != null) {
      return cached;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
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
    final picture = recorder.endRecording();
    if (_cache.length > 6) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = picture;
    return picture;
  }
}

class _GridCacheKey {
  _GridCacheKey(Size size)
    : width = size.width.round(),
      height = size.height.round();

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is _GridCacheKey && width == other.width && height == other.height;

  @override
  int get hashCode => Object.hash(width, height);
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

class _LinkStatusPanel extends StatelessWidget {
  const _LinkStatusPanel({
    required this.title,
    required this.primaryValue,
    this.caption,
    this.utilization,
  });

  final String title;
  final String primaryValue;
  final String? caption;
  final double? utilization;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          primaryValue,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              caption!,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        if (utilization != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: utilization!.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: const Color(0xFF101826),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Colors.tealAccent,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TemperaturePanel extends StatelessWidget {
  const _TemperaturePanel({
    required this.title,
    required this.primaryLabel,
    required this.secondaryLabel,
    this.progress,
  });

  final String title;
  final String primaryLabel;
  final String secondaryLabel;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          primaryLabel,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          secondaryLabel,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        if (progress != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: const Color(0xFF101826),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Colors.deepOrangeAccent,
                ),
              ),
            ),
          ),
      ],
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

class _ProcessPanel extends StatelessWidget {
  const _ProcessPanel({required this.host});

  final TwinHost host;

  @override
  Widget build(BuildContext context) {
    final processes = host.diagnostics.topProcesses
        .take(3)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '상위 프로세스',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
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
    );
  }
}

class _InterfacePanel extends StatelessWidget {
  const _InterfacePanel({required this.host});

  final TwinHost host;

  @override
  Widget build(BuildContext context) {
    final interfaces = host.diagnostics.interfaces
        .take(2)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '네트워크 인터페이스',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
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
    );
  }
}

class _StoragePanel extends StatelessWidget {
  const _StoragePanel({required this.host});

  final TwinHost host;

  @override
  Widget build(BuildContext context) {
    final disks = host.diagnostics.disks.take(2).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '스토리지',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
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
    );
  }
}

// === Widget dock system =====================================================

const int _kDockColumns = 4;
const int _kDockRows = 14;

const List<_WidgetPlacementSeed> _defaultDockPlacements = [
  _WidgetPlacementSeed(
    type: SidebarWidgetType.globalMetrics,
    wing: SidebarWing.left,
    column: 0,
    row: 0,
  ),
  _WidgetPlacementSeed(
    type: SidebarWidgetType.globalLink,
    wing: SidebarWing.left,
    column: 0,
    row: 4,
  ),
  _WidgetPlacementSeed(
    type: SidebarWidgetType.globalTemperature,
    wing: SidebarWing.left,
    column: 0,
    row: 6,
  ),
  _WidgetPlacementSeed(
    type: SidebarWidgetType.commandConsole,
    wing: SidebarWing.left,
    column: 0,
    row: 8,
  ),
  _WidgetPlacementSeed(
    type: SidebarWidgetType.telemetry,
    wing: SidebarWing.right,
    column: 0,
    row: 0,
  ),
  _WidgetPlacementSeed(
    type: SidebarWidgetType.hostLink,
    wing: SidebarWing.right,
    column: 0,
    row: 4,
  ),
  _WidgetPlacementSeed(
    type: SidebarWidgetType.hostTemperature,
    wing: SidebarWing.right,
    column: 0,
    row: 6,
  ),
  _WidgetPlacementSeed(
    type: SidebarWidgetType.processes,
    wing: SidebarWing.right,
    column: 0,
    row: 8,
  ),
  _WidgetPlacementSeed(
    type: SidebarWidgetType.network,
    wing: SidebarWing.right,
    column: 0,
    row: 10,
  ),
  _WidgetPlacementSeed(
    type: SidebarWidgetType.storage,
    wing: SidebarWing.right,
    column: 0,
    row: 12,
  ),
];

typedef _SidebarWidgetBuilder =
    Widget Function(BuildContext context, _WidgetBuildContext data);

class _WidgetBuildContext {
  const _WidgetBuildContext({
    required this.frame,
    required this.selectedHost,
    required this.samples,
    required this.constraints,
  });

  final TwinStateFrame frame;
  final TwinHost? selectedHost;
  final List<_MetricSample> samples;
  final BoxConstraints constraints;
}

class _WidgetBlueprint {
  const _WidgetBlueprint({
    required this.type,
    required this.displayName,
    required this.description,
    required this.allowedWings,
    required this.widthUnits,
    required this.heightUnits,
    required this.builder,
    this.requiresHost = false,
  });

  final SidebarWidgetType type;
  final String displayName;
  final String description;
  final Set<SidebarWing> allowedWings;
  final int widthUnits;
  final int heightUnits;
  final bool requiresHost;
  final _SidebarWidgetBuilder builder;
}

const Map<SidebarWidgetType, _WidgetBlueprint> _widgetBlueprints = {
  SidebarWidgetType.globalMetrics: _WidgetBlueprint(
    type: SidebarWidgetType.globalMetrics,
    displayName: '전역 지표',
    description: '클러스터 CPU·메모리 부하를 요약합니다.',
    allowedWings: {SidebarWing.left},
    widthUnits: 4,
    heightUnits: 4,
    builder: _buildGlobalMetricsWidget,
  ),
  SidebarWidgetType.globalLink: _WidgetBlueprint(
    type: SidebarWidgetType.globalLink,
    displayName: '링크 상태',
    description: '전체 트래픽과 용량 대비 활용률을 표시합니다.',
    allowedWings: {SidebarWing.left},
    widthUnits: 4,
    heightUnits: 2,
    builder: _buildGlobalLinkWidget,
  ),
  SidebarWidgetType.globalTemperature: _WidgetBlueprint(
    type: SidebarWidgetType.globalTemperature,
    displayName: '온도 현황',
    description: '최대·평균 CPU 온도를 모니터링합니다.',
    allowedWings: {SidebarWing.left},
    widthUnits: 4,
    heightUnits: 2,
    builder: _buildGlobalTemperatureWidget,
  ),
  SidebarWidgetType.commandConsole: _WidgetBlueprint(
    type: SidebarWidgetType.commandConsole,
    displayName: '원격 자동화',
    description: '명령 전송 · 최근 요청을 관리합니다.',
    allowedWings: {SidebarWing.left},
    widthUnits: 4,
    heightUnits: 4,
    builder: _buildCommandConsoleWidget,
  ),
  SidebarWidgetType.telemetry: _WidgetBlueprint(
    type: SidebarWidgetType.telemetry,
    displayName: '실시간 텔레메트리',
    description: '선택한 노드의 CPU·메모리를 HUD 형태로 제공합니다.',
    allowedWings: {SidebarWing.right},
    widthUnits: 4,
    heightUnits: 4,
    requiresHost: true,
    builder: _buildTelemetryWidget,
  ),
  SidebarWidgetType.hostLink: _WidgetBlueprint(
    type: SidebarWidgetType.hostLink,
    displayName: '링크 상태',
    description: '노드별 실시간 링크 속도를 표시합니다.',
    allowedWings: {SidebarWing.right},
    widthUnits: 4,
    heightUnits: 2,
    requiresHost: true,
    builder: _buildHostLinkWidget,
  ),
  SidebarWidgetType.hostTemperature: _WidgetBlueprint(
    type: SidebarWidgetType.hostTemperature,
    displayName: '온도 현황',
    description: '노드별 CPU/GPU 온도를 추적합니다.',
    allowedWings: {SidebarWing.right},
    widthUnits: 4,
    heightUnits: 2,
    requiresHost: true,
    builder: _buildHostTemperatureWidget,
  ),
  SidebarWidgetType.processes: _WidgetBlueprint(
    type: SidebarWidgetType.processes,
    displayName: '상위 프로세스',
    description: 'CPU 사용량 기준 상위 프로세스를 보여줍니다.',
    allowedWings: {SidebarWing.right},
    widthUnits: 4,
    heightUnits: 2,
    requiresHost: true,
    builder: _buildProcessWidget,
  ),
  SidebarWidgetType.network: _WidgetBlueprint(
    type: SidebarWidgetType.network,
    displayName: '네트워크 인터페이스',
    description: '주요 인터페이스의 양방향 트래픽과 상태를 시각화합니다.',
    allowedWings: {SidebarWing.right},
    widthUnits: 4,
    heightUnits: 2,
    requiresHost: true,
    builder: _buildNetworkWidget,
  ),
  SidebarWidgetType.storage: _WidgetBlueprint(
    type: SidebarWidgetType.storage,
    displayName: '스토리지',
    description: '스토리지 볼륨과 사용량을 표시합니다.',
    allowedWings: {SidebarWing.right},
    widthUnits: 4,
    heightUnits: 2,
    requiresHost: true,
    builder: _buildStorageWidget,
  ),
};

Widget _buildGlobalMetricsWidget(
  BuildContext context,
  _WidgetBuildContext data,
) => _SidebarOverviewCard(frame: data.frame);

Widget _buildGlobalLinkWidget(BuildContext context, _WidgetBuildContext data) {
  final frame = data.frame;
  final throughput = frame.estimatedThroughput;
  final capacity = frame.totalLinkCapacity;
  final utilization = capacity > 0
      ? (throughput / capacity).clamp(0.0, 1.0)
      : null;
  return _GlassTile(
    child: _LinkStatusPanel(
      title: '클러스터 링크',
      primaryValue: '${throughput.toStringAsFixed(2)} Gbps',
      caption: capacity > 0
          ? '용량 ${capacity.toStringAsFixed(2)} Gbps'
          : '용량 정보 없음',
      utilization: utilization,
    ),
  );
}

Widget _buildGlobalTemperatureWidget(
  BuildContext context,
  _WidgetBuildContext data,
) {
  final frame = data.frame;
  final maxTemp = frame.maxCpuTemperature > 0 ? frame.maxCpuTemperature : null;
  final avgTemp = frame.averageCpuTemperature > 0
      ? frame.averageCpuTemperature
      : null;
  return _GlassTile(
    child: _TemperaturePanel(
      title: '클러스터 온도',
      primaryLabel: maxTemp != null ? '${maxTemp.toStringAsFixed(1)}℃' : 'N/A',
      secondaryLabel: avgTemp != null
          ? '평균 ${avgTemp.toStringAsFixed(1)}℃'
          : '센서 없음',
      progress: maxTemp != null ? (maxTemp / 110).clamp(0.0, 1.0) : null,
    ),
  );
}

Widget _buildCommandConsoleWidget(
  BuildContext context,
  _WidgetBuildContext data,
) => _CommandConsoleCard(frame: data.frame, selectedHost: data.selectedHost);

Widget _buildTelemetryWidget(BuildContext context, _WidgetBuildContext data) {
  final host = data.selectedHost;
  if (host == null) {
    return const _DockHostGuard(message: '노드를 선택하여 연결 상태를 확인하세요.');
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _OverlayHeader(host: host, theme: Theme.of(context).textTheme),
      const SizedBox(height: 12),
      Expanded(
        child: _RealtimeTelemetryCard(host: host, samples: data.samples),
      ),
    ],
  );
}

Widget _buildHostLinkWidget(BuildContext context, _WidgetBuildContext data) {
  final host = data.selectedHost;
  if (host == null) {
    return const _DockHostGuard(message: '노드를 선택하여 링크를 확인하세요.');
  }
  final latest = data.samples.isNotEmpty ? data.samples.last : null;
  final throughput = host.metrics.netThroughputGbps ?? latest?.throughput ?? 0;
  final capacity = host.metrics.netCapacityGbps;
  final utilization = capacity != null && capacity > 0
      ? (throughput / capacity).clamp(0.0, 1.0)
      : null;
  return _GlassTile(
    child: _LinkStatusPanel(
      title: host.displayName,
      primaryValue: throughput > 0
          ? '${throughput.toStringAsFixed(2)} Gbps'
          : '데이터 없음',
      caption: capacity != null
          ? '용량 ${capacity.toStringAsFixed(2)} Gbps'
          : '용량 정보 없음',
      utilization: utilization,
    ),
  );
}

Widget _buildHostTemperatureWidget(
  BuildContext context,
  _WidgetBuildContext data,
) {
  final host = data.selectedHost;
  if (host == null) {
    return const _DockHostGuard(message: '노드를 선택하여 온도를 확인하세요.');
  }
  final cpuTemp = host.cpuTemperature;
  final gpuTemp = host.gpuTemperature;
  final primary = cpuTemp ?? gpuTemp;
  final secondary = () {
    if (cpuTemp != null && gpuTemp != null) {
      return 'GPU ${gpuTemp.toStringAsFixed(1)}℃';
    }
    if (cpuTemp != null) {
      return 'GPU 센서 없음';
    }
    if (gpuTemp != null) {
      return 'GPU ${gpuTemp.toStringAsFixed(1)}℃';
    }
    return '센서 없음';
  }();
  return _GlassTile(
    child: _TemperaturePanel(
      title: host.displayName,
      primaryLabel: primary != null
          ? '${primary.toStringAsFixed(1)}℃'
          : '데이터 없음',
      secondaryLabel: secondary,
      progress: primary != null ? (primary / 110).clamp(0.0, 1.0) : null,
    ),
  );
}

Widget _buildProcessWidget(BuildContext context, _WidgetBuildContext data) {
  final host = data.selectedHost;
  if (host == null) {
    return const _DockHostGuard(message: '대상을 선택하면 프로세스를 보여줍니다.');
  }
  return _ProcessPanel(host: host);
}

Widget _buildNetworkWidget(BuildContext context, _WidgetBuildContext data) {
  final host = data.selectedHost;
  if (host == null) {
    return const _DockHostGuard(message: '네트워크 인터페이스는 선택된 노드 기준으로 표시됩니다.');
  }
  return _InterfacePanel(host: host);
}

Widget _buildStorageWidget(BuildContext context, _WidgetBuildContext data) {
  final host = data.selectedHost;
  if (host == null) {
    return const _DockHostGuard(message: '스토리지 사용량을 보려면 노드를 선택하세요.');
  }
  return _StoragePanel(host: host);
}

class _WidgetPlacementSeed {
  const _WidgetPlacementSeed({
    required this.type,
    required this.wing,
    required this.column,
    required this.row,
  });

  final SidebarWidgetType type;
  final SidebarWing wing;
  final int column;
  final int row;
}

class _WidgetPlacement {
  const _WidgetPlacement({
    required this.id,
    required this.type,
    required this.wing,
    required this.column,
    required this.row,
    required this.widthUnits,
    required this.heightUnits,
  });

  final String id;
  final SidebarWidgetType type;
  final SidebarWing wing;
  final int column;
  final int row;
  final int widthUnits;
  final int heightUnits;

  bool overlaps(
    int otherColumn,
    int otherRow,
    int otherWidth,
    int otherHeight,
  ) {
    final rect = Rect.fromLTWH(
      column.toDouble(),
      row.toDouble(),
      widthUnits.toDouble(),
      heightUnits.toDouble(),
    );
    final other = Rect.fromLTWH(
      otherColumn.toDouble(),
      otherRow.toDouble(),
      otherWidth.toDouble(),
      otherHeight.toDouble(),
    );
    return rect.overlaps(other);
  }

  _WidgetPlacement copyWith({int? column, int? row}) => _WidgetPlacement(
    id: id,
    type: type,
    wing: wing,
    column: column ?? this.column,
    row: row ?? this.row,
    widthUnits: widthUnits,
    heightUnits: heightUnits,
  );
}

class _WidgetDockController extends ChangeNotifier {
  _WidgetDockController({
    required List<_WidgetPlacementSeed> initialPlacements,
  }) {
    for (final seed in initialPlacements) {
      final blueprint = _widgetBlueprints[seed.type]!;
      if (!blueprint.allowedWings.contains(seed.wing)) {
        continue;
      }
      final placement = _WidgetPlacement(
        id: 'seed_${_nextId++}',
        type: seed.type,
        wing: seed.wing,
        column: seed.column,
        row: seed.row,
        widthUnits: blueprint.widthUnits,
        heightUnits: blueprint.heightUnits,
      );
      if (!canPlace(seed.wing, seed.type, seed.column, seed.row)) {
        continue;
      }
      _placements[seed.wing]!.add(placement);
      _activeTypes.add(seed.type);
    }
    _sortPlacements();
  }

  final Map<SidebarWing, List<_WidgetPlacement>> _placements = {
    SidebarWing.left: <_WidgetPlacement>[],
    SidebarWing.right: <_WidgetPlacement>[],
  };
  final Set<SidebarWidgetType> _activeTypes = {};
  int _nextId = 0;

  List<_WidgetPlacement> placementsFor(SidebarWing wing) =>
      List.unmodifiable(_placements[wing]!);

  Set<SidebarWidgetType> get activeTypes => Set.unmodifiable(_activeTypes);

  bool canPlace(
    SidebarWing wing,
    SidebarWidgetType type,
    int column,
    int row, {
    String? ignoreId,
  }) {
    final blueprint = _widgetBlueprints[type]!;
    if (!blueprint.allowedWings.contains(wing)) {
      return false;
    }
    if (column < 0 || row < 0) {
      return false;
    }
    if (column + blueprint.widthUnits > _kDockColumns) {
      return false;
    }
    if (row + blueprint.heightUnits > _kDockRows) {
      return false;
    }
    if (ignoreId == null && _activeTypes.contains(type)) {
      return false;
    }
    for (final placement in _placements[wing]!) {
      if (placement.id == ignoreId) continue;
      if (placement.overlaps(
        column,
        row,
        blueprint.widthUnits,
        blueprint.heightUnits,
      )) {
        return false;
      }
    }
    return true;
  }

  void addPlacement(
    SidebarWidgetType type,
    SidebarWing wing,
    int column,
    int row,
  ) {
    final blueprint = _widgetBlueprints[type]!;
    if (!canPlace(wing, type, column, row)) {
      return;
    }
    final placement = _WidgetPlacement(
      id: 'dock_${_nextId++}',
      type: type,
      wing: wing,
      column: column,
      row: row,
      widthUnits: blueprint.widthUnits,
      heightUnits: blueprint.heightUnits,
    );
    _placements[wing]!.add(placement);
    _activeTypes.add(type);
    _sortPlacements();
    notifyListeners();
  }

  void movePlacement(String id, SidebarWing wing, int column, int row) {
    final list = _placements[wing]!;
    final index = list.indexWhere((placement) => placement.id == id);
    if (index == -1) return;
    final placement = list[index];
    if (!canPlace(wing, placement.type, column, row, ignoreId: id)) {
      return;
    }
    list[index] = placement.copyWith(column: column, row: row);
    _sortPlacements();
    notifyListeners();
  }

  void removePlacement(String id) {
    for (final wing in SidebarWing.values) {
      final list = _placements[wing]!;
      final index = list.indexWhere((placement) => placement.id == id);
      if (index == -1) continue;
      final removed = list.removeAt(index);
      _activeTypes.remove(removed.type);
      notifyListeners();
      return;
    }
  }

  void _sortPlacements() {
    for (final wing in SidebarWing.values) {
      _placements[wing]!.sort((a, b) {
        final rowCompare = a.row.compareTo(b.row);
        if (rowCompare != 0) return rowCompare;
        return a.column.compareTo(b.column);
      });
    }
  }
}

class _WidgetGridPanel extends StatefulWidget {
  const _WidgetGridPanel({
    required this.wing,
    required this.controller,
    required this.frame,
    required this.selectedHost,
    required this.samples,
    required this.emptyLabel,
  });

  final SidebarWing wing;
  final _WidgetDockController controller;
  final TwinStateFrame frame;
  final TwinHost? selectedHost;
  final List<_MetricSample> samples;
  final String emptyLabel;

  @override
  State<_WidgetGridPanel> createState() => _WidgetGridPanelState();
}

class _WidgetGridPanelState extends State<_WidgetGridPanel> {
  final GlobalKey _gridKey = GlobalKey();
  _DropIndicator? _indicator;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final placements = widget.controller.placementsFor(widget.wing);
        return LayoutBuilder(
          builder: (context, constraints) {
            final spec = _GridSpec.compute(constraints);
            final children = <Widget>[
              Positioned.fill(
                child: CustomPaint(painter: _GridBackgroundPainter(spec: spec)),
              ),
            ];

            if (placements.isEmpty) {
              children.add(
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.emptyLabel,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }

            for (final placement in placements) {
              children.add(
                _DockedWidgetTile(
                  key: ValueKey(placement.id),
                  placement: placement,
                  spec: spec,
                  controller: widget.controller,
                  frame: widget.frame,
                  selectedHost: widget.selectedHost,
                  samples: widget.samples,
                ),
              );
            }

            if (_indicator != null) {
              final rect = spec.rectFor(
                _indicator!.column,
                _indicator!.row,
                _indicator!.widthUnits,
                _indicator!.heightUnits,
              );
              children.add(
                Positioned(
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color:
                          (_indicator!.isValid
                                  ? Colors.tealAccent
                                  : Colors.redAccent)
                              .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _indicator!.isValid
                            ? Colors.tealAccent.withValues(alpha: 0.6)
                            : Colors.redAccent,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              );
            }

            final panelHeight = math.min(
              spec.totalHeight,
              constraints.maxHeight,
            );

            return Align(
              alignment: Alignment.center,
              child: SizedBox(
                key: _gridKey,
                width: constraints.maxWidth,
                height: panelHeight,
                child: DragTarget<_DockDragPayload>(
                  onWillAcceptWithDetails: (details) =>
                      details.data.allowedWings.contains(widget.wing),
                  onMove: (details) => _handleDrag(details, spec),
                  onLeave: (_) => setState(() => _indicator = null),
                  onAcceptWithDetails: (details) => _handleDrop(details, spec),
                  builder: (context, _, __) => Stack(children: children),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _handleDrag(
    DragTargetDetails<_DockDragPayload> details,
    _GridSpec spec,
  ) {
    final payload = details.data;
    final renderBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return;
    }
    if (!payload.allowedWings.contains(widget.wing)) {
      setState(() => _indicator = null);
      return;
    }
    final local = renderBox.globalToLocal(details.offset);
    final cell = spec.cellForOffset(local);
    if (cell == null) {
      setState(() => _indicator = null);
      return;
    }
    final canPlace = widget.controller.canPlace(
      widget.wing,
      payload.type,
      cell.column,
      cell.row,
      ignoreId: payload.placementId,
    );
    setState(() {
      _indicator = _DropIndicator(
        column: cell.column,
        row: cell.row,
        widthUnits: payload.widthUnits,
        heightUnits: payload.heightUnits,
        isValid: canPlace,
      );
    });
  }

  void _handleDrop(
    DragTargetDetails<_DockDragPayload> details,
    _GridSpec spec,
  ) {
    final indicator = _indicator;
    final payload = details.data;
    if (indicator == null) {
      return;
    }
    if (!indicator.isValid) {
      _showInvalidSnack();
      setState(() => _indicator = null);
      return;
    }
    if (payload.placementId != null) {
      widget.controller.movePlacement(
        payload.placementId!,
        widget.wing,
        indicator.column,
        indicator.row,
      );
    } else {
      widget.controller.addPlacement(
        payload.type,
        widget.wing,
        indicator.column,
        indicator.row,
      );
    }
    setState(() => _indicator = null);
  }

  void _showInvalidSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('해당 위치에 배치할 수 없습니다.'),
        duration: Duration(milliseconds: 900),
      ),
    );
  }
}

class _DockedWidgetTile extends StatelessWidget {
  const _DockedWidgetTile({
    super.key,
    required this.placement,
    required this.spec,
    required this.controller,
    required this.frame,
    required this.selectedHost,
    required this.samples,
  });

  final _WidgetPlacement placement;
  final _GridSpec spec;
  final _WidgetDockController controller;
  final TwinStateFrame frame;
  final TwinHost? selectedHost;
  final List<_MetricSample> samples;

  @override
  Widget build(BuildContext context) {
    final blueprint = _widgetBlueprints[placement.type]!;
    final rect = spec.rectFor(
      placement.column,
      placement.row,
      placement.widthUnits,
      placement.heightUnits,
    );
    final payload = _DockDragPayload.existing(
      placementId: placement.id,
      type: placement.type,
      widthUnits: placement.widthUnits,
      heightUnits: placement.heightUnits,
      allowedWings: blueprint.allowedWings,
    );
    final sizeLabel = '${blueprint.widthUnits}×${blueprint.heightUnits}';

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x220C1A2A),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x331B2333)),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 34, 20, 20),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final data = _WidgetBuildContext(
                      frame: frame,
                      selectedHost: selectedHost,
                      samples: samples,
                      constraints: constraints,
                    );
                    return blueprint.builder(context, data);
                  },
                ),
              ),
            ),
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: Center(child: _SizeBadge(label: sizeLabel)),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                splashRadius: 18,
                icon: const Icon(Icons.close, color: Colors.white38),
                onPressed: () => controller.removePlacement(placement.id),
              ),
            ),
            Positioned(
              left: 8,
              top: 6,
              child: LongPressDraggable<_DockDragPayload>(
                data: payload,
                feedback: Opacity(
                  opacity: 0.9,
                  child: SizedBox(
                    width: rect.width,
                    height: rect.height,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0x330C1A2A),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.tealAccent.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const _DockGripIcon(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockGripIcon extends StatelessWidget {
  const _DockGripIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 24,
      decoration: BoxDecoration(
        color: const Color(0x330C1A2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x331B2333)),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.drag_indicator, size: 16, color: Colors.white54),
    );
  }
}

class _SizeBadge extends StatelessWidget {
  const _SizeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x330C1A2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x221B2333)),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white54, fontSize: 11),
      ),
    );
  }
}

class _DockHostGuard extends StatelessWidget {
  const _DockHostGuard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _WidgetPaletteOverlay extends StatelessWidget {
  const _WidgetPaletteOverlay({
    required this.controller,
    required this.onClose,
  });

  final _WidgetDockController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final active = controller.activeTypes;
    final leftBlueprints = _widgetBlueprints.values
        .where((blueprint) => blueprint.allowedWings.contains(SidebarWing.left))
        .toList(growable: false);
    final rightBlueprints = _widgetBlueprints.values
        .where(
          (blueprint) => blueprint.allowedWings.contains(SidebarWing.right),
        )
        .toList(growable: false);

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Material(
          color: const Color(0xF00A111C),
          borderRadius: BorderRadius.circular(28),
          elevation: 24,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Widget Dock',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: onClose,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '필요한 모듈을 길게 눌러 사이드바 격자에 드롭하세요. 이미 배치된 항목은 다시 추가할 수 없습니다.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 18),
                  _WidgetPaletteSection(
                    title: '좌측 패널',
                    blueprints: leftBlueprints,
                    activeTypes: active,
                  ),
                  const SizedBox(height: 18),
                  _WidgetPaletteSection(
                    title: '우측 패널',
                    blueprints: rightBlueprints,
                    activeTypes: active,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WidgetPaletteSection extends StatelessWidget {
  const _WidgetPaletteSection({
    required this.title,
    required this.blueprints,
    required this.activeTypes,
  });

  final String title;
  final List<_WidgetBlueprint> blueprints;
  final Set<SidebarWidgetType> activeTypes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: blueprints
              .map(
                (blueprint) => _WidgetPaletteChip(
                  blueprint: blueprint,
                  isActive: activeTypes.contains(blueprint.type),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _WidgetPaletteChip extends StatelessWidget {
  const _WidgetPaletteChip({required this.blueprint, required this.isActive});

  final _WidgetBlueprint blueprint;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      width: 200,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isActive ? const Color(0x220C1A2A) : const Color(0x330C1A2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? Colors.redAccent.withValues(alpha: 0.5)
              : const Color(0x331B2333),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            blueprint.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            blueprint.description,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );

    if (isActive) {
      return Stack(
        alignment: Alignment.center,
        children: [
          chip,
          const Icon(Icons.lock, size: 18, color: Colors.redAccent),
        ],
      );
    }

    return LongPressDraggable<_DockDragPayload>(
      data: _DockDragPayload.fromBlueprint(blueprint),
      feedback: Material(color: Colors.transparent, child: chip),
      child: chip,
    );
  }
}

class _WidgetPaletteButton extends StatelessWidget {
  const _WidgetPaletteButton({required this.isActive, required this.onPressed});

  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: isActive ? Colors.tealAccent : Colors.white70,
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.widgets_outlined, size: 16),
      label: Text(isActive ? '위젯 닫기' : '위젯'),
    );
  }
}

class _GridSpec {
  const _GridSpec({
    required this.cellSize,
    required this.padding,
    required this.gap,
    required this.columns,
    required this.rows,
  });

  final double cellSize;
  final EdgeInsets padding;
  final double gap;
  final int columns;
  final int rows;

  static _GridSpec compute(BoxConstraints constraints) {
    const padding = EdgeInsets.symmetric(horizontal: 12, vertical: 12);
    const gap = 12.0;
    final widthAvailable =
        (constraints.maxWidth - padding.horizontal) - gap * (_kDockColumns - 1);
    final usableWidth = math.max(160.0, widthAvailable);
    final sizeFromWidth = usableWidth / _kDockColumns;

    final heightAvailable =
        (constraints.maxHeight - padding.vertical) - gap * (_kDockRows - 1);
    final sizeFromHeight = heightAvailable > 0
        ? heightAvailable / _kDockRows
        : sizeFromWidth;

    final cellSize = math.max(20.0, math.min(sizeFromWidth, sizeFromHeight));
    return _GridSpec(
      cellSize: cellSize,
      padding: padding,
      gap: gap,
      columns: _kDockColumns,
      rows: _kDockRows,
    );
  }

  double spanWidth(int widthUnits) =>
      widthUnits * cellSize + (widthUnits - 1) * gap;

  double spanHeight(int heightUnits) =>
      heightUnits * cellSize + (heightUnits - 1) * gap;

  double get totalHeight =>
      padding.vertical + rows * cellSize + (rows - 1) * gap;

  Rect rectFor(int column, int row, int widthUnits, int heightUnits) =>
      Rect.fromLTWH(
        padding.left + column * (cellSize + gap),
        padding.top + row * (cellSize + gap),
        spanWidth(widthUnits),
        spanHeight(heightUnits),
      );

  _GridCell? cellForOffset(Offset offset) {
    final dx = offset.dx - padding.left;
    final dy = offset.dy - padding.top;
    if (dx < 0 || dy < 0) return null;
    final column = (dx / (cellSize + gap)).floor();
    final row = (dy / (cellSize + gap)).floor();
    if (column < 0 || column >= columns || row < 0 || row >= rows) {
      return null;
    }
    final cellLeft = padding.left + column * (cellSize + gap);
    final cellTop = padding.top + row * (cellSize + gap);
    if (offset.dx > cellLeft + cellSize || offset.dy > cellTop + cellSize) {
      return null;
    }
    return _GridCell(column: column, row: row);
  }
}

class _GridCell {
  const _GridCell({required this.column, required this.row});

  final int column;
  final int row;
}

class _GridBackgroundPainter extends CustomPainter {
  const _GridBackgroundPainter({required this.spec});

  final _GridSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x110B1B2A)
      ..style = PaintingStyle.fill;
    for (var row = 0; row < spec.rows; row++) {
      for (var col = 0; col < spec.columns; col++) {
        final rect = spec.rectFor(col, row, 1, 1).deflate(4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(8)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DockDragPayload {
  const _DockDragPayload._({
    required this.type,
    required this.allowedWings,
    required this.widthUnits,
    required this.heightUnits,
    this.placementId,
  });

  factory _DockDragPayload.fromBlueprint(_WidgetBlueprint blueprint) =>
      _DockDragPayload._(
        type: blueprint.type,
        allowedWings: blueprint.allowedWings,
        widthUnits: blueprint.widthUnits,
        heightUnits: blueprint.heightUnits,
      );

  factory _DockDragPayload.existing({
    required String placementId,
    required SidebarWidgetType type,
    required int widthUnits,
    required int heightUnits,
    required Set<SidebarWing> allowedWings,
  }) => _DockDragPayload._(
    placementId: placementId,
    type: type,
    allowedWings: allowedWings,
    widthUnits: widthUnits,
    heightUnits: heightUnits,
  );

  final String? placementId;
  final SidebarWidgetType type;
  final Set<SidebarWing> allowedWings;
  final int widthUnits;
  final int heightUnits;
}

class _DropIndicator {
  const _DropIndicator({
    required this.column,
    required this.row,
    required this.widthUnits,
    required this.heightUnits,
    required this.isValid,
  });

  final int column;
  final int row;
  final int widthUnits;
  final int heightUnits;
  final bool isValid;
}
