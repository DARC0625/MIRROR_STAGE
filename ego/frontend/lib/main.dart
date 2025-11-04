import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/models/command_models.dart';
import 'core/models/twin_models.dart';
import 'core/services/command_service.dart';
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
    );

    return MaterialApp(
      title: 'MIRROR STAGE',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        textTheme: GoogleFonts.ibmPlexSansTextTheme(
          baseTheme.textTheme,
        ).apply(bodyColor: Colors.white, displayColor: Colors.white),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF05080D),
          foregroundColor: colorScheme.onSurface,
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
        if (selectedHost == null && frame.hosts.isNotEmpty) {
          selectedHost = frame.hosts.first;
          final fallbackName = selectedHost.hostname;
          if (_selectedHostName != fallbackName) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (_selectedHostName != fallbackName) {
                setState(() => _selectedHostName = fallbackName);
              }
            });
          }
        }

        final heatMax = frame.maxCpuTemperature > 0
            ? frame.maxCpuTemperature
            : 100.0;

        return Scaffold(
          backgroundColor: const Color(0xFF05080D),
          body: Column(
            children: [
              _CommandAppBar(
                frame: frame,
                mode: _viewportMode,
                onModeChange: _setViewportMode,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 1080;
                    final stage = _TwinStage(
                      frame: frame,
                      mode: _viewportMode,
                      selectedHost: selectedHost,
                      heatMax: heatMax,
                      onSelectHost: _selectHost,
                    );

                    if (isWide) {
                      return Row(
                        children: [
                          _Sidebar(
                            frame: frame,
                            mode: _viewportMode,
                            onModeChange: _setViewportMode,
                          ),
                          Expanded(child: stage),
                          _InsightPanel(
                            frame: frame,
                            selectedHost: selectedHost,
                            onSelectHost: _selectHost,
                          ),
                        ],
                      );
                    }

                    return Column(
                      children: [
                        Expanded(child: stage),
                        SizedBox(
                          height: constraints.maxHeight * .4,
                          child: _InsightPanel(
                            frame: frame,
                            selectedHost: selectedHost,
                            onSelectHost: _selectHost,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.frame,
    required this.mode,
    required this.onModeChange,
  });

  final TwinStateFrame frame;
  final TwinViewportMode mode;
  final ValueChanged<TwinViewportMode> onModeChange;

  @override
  Widget build(BuildContext context) {
    final cpuLoad = frame.averageCpuLoad.clamp(0, 100).toDouble();
    final memoryPercent = frame.memoryUtilizationPercent
        .clamp(0, 100)
        .toDouble();
    final throughput = frame.estimatedThroughput;
    final capacity = frame.totalLinkCapacity;
    final averageTemp = frame.averageCpuTemperature;
    final peakTemp = frame.maxCpuTemperature;
    final memorySummary = frame.totalMemoryCapacityGb > 0
        ? '${frame.totalMemoryUsedGb.toStringAsFixed(1)}/${frame.totalMemoryCapacityGb.toStringAsFixed(1)} GB'
        : '${frame.averageMemoryLoad.toStringAsFixed(1)}%';

    return Container(
      width: 300,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFF11141D))),
        gradient: LinearGradient(
          colors: [Color(0xFF060910), Color(0xFF020307)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '실시간 개요',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            Center(
              child: _AnalogGauge(
                label: '평균 CPU',
                value: cpuLoad,
                maxValue: 100,
                units: '%',
                decimals: 1,
                subtitle: averageTemp > 0
                    ? '평균 온도 ${averageTemp.toStringAsFixed(1)}℃'
                    : null,
              ),
            ),
            const SizedBox(height: 28),
            Center(
              child: _AnalogGauge(
                label: '메모리 사용률',
                value: memoryPercent,
                maxValue: 100,
                units: '%',
                subtitle: memorySummary,
                startColor: const Color(0xFF38BDF8),
                endColor: Colors.deepOrangeAccent,
                size: 180,
              ),
            ),
            const SizedBox(height: 28),
            _MetricTile(
              label: '총 스루풋',
              value: '${throughput.toStringAsFixed(2)} Gbps',
              caption: capacity > 0
                  ? '총 용량 ${capacity.toStringAsFixed(2)} Gbps'
                  : null,
            ),
            _MetricTile(
              label: '링크 활용률',
              value:
                  '${(frame.linkUtilization * 100).clamp(0.0, 100.0).toStringAsFixed(1)}%',
            ),
            _MetricTile(
              label: '피크 온도',
              value: peakTemp > 0 ? '${peakTemp.toStringAsFixed(1)}℃' : 'N/A',
            ),
            const SizedBox(height: 32),
            Text(
              '뷰 전환',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.white70,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 12),
            _NavButton(
              label: '글로벌 토폴로지',
              isActive: mode == TwinViewportMode.topology,
              onPressed: () => onModeChange(TwinViewportMode.topology),
            ),
            const SizedBox(height: 10),
            _NavButton(
              label: '온도 히트맵',
              isActive: mode == TwinViewportMode.heatmap,
              onPressed: () => onModeChange(TwinViewportMode.heatmap),
            ),
            const SizedBox(height: 10),
            _NavButton(
              label: '자동화 타임라인',
              isActive: false,
              onPressed: null,
              isEnabled: false,
            ),
            const SizedBox(height: 32),
            Text(
              '생성 시각: ${frame.generatedAt.toLocal().toIso8601String()}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandAppBar extends StatelessWidget {
  const _CommandAppBar({
    required this.frame,
    required this.mode,
    required this.onModeChange,
  });

  final TwinStateFrame frame;
  final TwinViewportMode mode;
  final ValueChanged<TwinViewportMode> onModeChange;

  @override
  Widget build(BuildContext context) {
    final stats = [
      _StatusChip(label: '내부망', value: '10.0.0.0/24'),
      _StatusChip(
        label: '온라인 호스트',
        value: '${frame.onlineHosts}/${frame.totalHosts}',
      ),
      _StatusChip(
        label: 'CPU',
        value: '${frame.averageCpuLoad.toStringAsFixed(1)}%',
      ),
      _StatusChip(
        label: '메모리',
        value: frame.totalMemoryCapacityGb > 0
            ? '${frame.totalMemoryUsedGb.toStringAsFixed(1)}/${frame.totalMemoryCapacityGb.toStringAsFixed(1)} GB'
            : '${frame.averageMemoryLoad.toStringAsFixed(1)}%',
      ),
      _StatusChip(
        label: '스루풋',
        value: '${frame.estimatedThroughput.toStringAsFixed(2)} Gbps',
      ),
      _StatusChip(
        label: '피크 온도',
        value: frame.maxCpuTemperature > 0
            ? '${frame.maxCpuTemperature.toStringAsFixed(1)}℃'
            : 'N/A',
      ),
    ];

    return Container(
      height: 78,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF05080D), Color(0xFF04060A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(bottom: BorderSide(color: Color(0x331B2333))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      child: Row(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF0D2A3F),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x332FD0FF)),
                ),
                child: const Icon(
                  Icons.radar,
                  color: Colors.tealAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'MIRROR STAGE',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(width: 32),
          _ViewModeToggle(mode: mode, onModeChange: onModeChange),
          const Spacer(),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: stats,
                ),
              ),
            ),
          ),
        ],
      ),
    );
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

class _TwinViewport extends StatelessWidget {
  const _TwinViewport({
    required this.frame,
    required this.height,
    required this.mode,
    required this.selectedHost,
    required this.heatMax,
    required this.onSelectHost,
    required this.cameraFocus,
  });

  final TwinStateFrame frame;
  final double height;
  final TwinViewportMode mode;
  final String? selectedHost;
  final double heatMax;
  final ValueChanged<String> onSelectHost;
  final TwinPosition cameraFocus;

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
                  }
                },
                child: CustomPaint(
                  painter: _TwinScenePainter(
                    frame,
                    mode: mode,
                    selectedHost: selectedHost,
                    heatMax: heatMax,
                    cameraFocus: cameraFocus,
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
  });

  final TwinStateFrame frame;
  final TwinViewportMode mode;
  final TwinHost? selectedHost;
  final double heatMax;
  final ValueChanged<String> onSelectHost;

  @override
  State<_TwinStage> createState() => _TwinStageState();
}

class _TwinStageState extends State<_TwinStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cameraController;
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
                    cameraFocus: focus,
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: widget.selectedHost == null,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Align(
                        alignment: Alignment.topRight,
                        child: _HostOverlay(
                          frame: widget.frame,
                          host: widget.selectedHost,
                        ),
                      ),
                    ),
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

class _InsightPanel extends StatefulWidget {
  const _InsightPanel({
    required this.frame,
    required this.selectedHost,
    required this.onSelectHost,
  });

  final TwinStateFrame frame;
  final TwinHost? selectedHost;
  final ValueChanged<String> onSelectHost;

  @override
  State<_InsightPanel> createState() => _InsightPanelState();
}

class _InsightPanelState extends State<_InsightPanel> {
  late final CommandService _commandService;
  final TextEditingController _commandController = TextEditingController();
  final TextEditingController _timeoutController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final List<CommandJob> _jobs = [];
  Timer? _pollTimer;
  bool _submitting = false;
  bool _loadingCommands = false;
  bool _hasMore = false;
  String? _formError;
  String? _targetHost;
  String? _filterHostname;
  CommandStatus? _filterStatus;
  int _currentPage = 1;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _commandService = CommandService();
    _targetHost = widget.selectedHost?.hostname;
    _filterHostname = widget.selectedHost?.hostname;
    _refreshCommands(reset: true);
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshCommands(reset: true),
    );
  }

  @override
  void didUpdateWidget(covariant _InsightPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hostChanged =
        widget.selectedHost?.hostname != oldWidget.selectedHost?.hostname;
    if (hostChanged && widget.selectedHost != null) {
      _targetHost ??= widget.selectedHost!.hostname;
      if (_filterHostname == null) {
        _filterHostname = widget.selectedHost!.hostname;
        _applyFilters();
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _commandService.dispose();
    _commandController.dispose();
    _timeoutController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshCommands({bool reset = false, int? page}) async {
    final nextPage = page ?? (reset ? 1 : _currentPage);
    setState(() => _loadingCommands = true);
    try {
      final result = await _commandService.listCommands(
        hostname: _filterHostname,
        status: _filterStatus,
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        page: nextPage,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _currentPage = result.page;
        if (reset || result.page == 1) {
          _jobs
            ..clear()
            ..addAll(result.items);
        } else {
          _jobs.addAll(result.items);
        }
        _hasMore = result.hasMore;
      });
    } catch (_) {
      // ignore transient errors for now
    } finally {
      if (mounted) {
        setState(() => _loadingCommands = false);
      }
    }
  }

  Future<void> _applyFilters() async {
    await _refreshCommands(reset: true, page: 1);
  }

  Future<void> _loadMore() async {
    if (_hasMore && !_loadingCommands) {
      await _refreshCommands(page: _currentPage + 1);
    }
  }

  void _clearFilters() {
    setState(() {
      _filterHostname = null;
      _filterStatus = null;
      _searchController.clear();
    });
    _applyFilters();
  }

  Future<void> _submitCommand() async {
    final host = _targetHost ?? widget.selectedHost?.hostname;
    if (host == null || host.isEmpty) {
      setState(() => _formError = '대상 호스트를 선택하세요.');
      return;
    }
    final command = _commandController.text.trim();
    if (command.isEmpty) {
      setState(() => _formError = '실행할 명령을 입력하세요.');
      return;
    }
    double? timeout;
    final timeoutText = _timeoutController.text.trim();
    if (timeoutText.isNotEmpty) {
      timeout = double.tryParse(timeoutText);
    }

    setState(() {
      _submitting = true;
      _formError = null;
    });
    try {
      await _commandService.createCommand(
        hostname: host,
        command: command,
        timeoutSeconds: timeout,
      );
      _commandController.clear();
      _timeoutController.clear();
      await _refreshCommands(reset: true);
    } catch (error) {
      setState(() => _formError = '명령 전송 실패: $error');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Color _statusColor(CommandStatus status) {
    switch (status) {
      case CommandStatus.pending:
        return Colors.amberAccent;
      case CommandStatus.running:
        return Colors.blueAccent;
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
    final theme = Theme.of(context);

    return Container(
      width: 360,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFF11141D))),
        gradient: LinearGradient(
          colors: [Color(0xFF080C14), Color(0xFF020408)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '원격 자동화',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '선택한 노드 혹은 지정된 대상에게 명령을 전송하고 실행 로그를 추적합니다.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
            ),
            const SizedBox(height: 16),
            _buildCommandForm(widget.selectedHost),
            const SizedBox(height: 20),
            Text(
              '필터',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            _buildCommandFilters(hosts),
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  '실행 로그',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '목록 새로고침',
                  onPressed: _loadingCommands
                      ? null
                      : () => _refreshCommands(reset: true),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildCommandList(),
            if (_hasMore)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _loadMore,
                  icon: const Icon(Icons.expand_more),
                  label: const Text('더 불러오기'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandForm(TwinHost? selectedHost) {
    final hostItems = widget.frame.hosts
        .where((host) => !host.isCore)
        .map(
          (host) => DropdownMenuItem<String>(
            value: host.hostname,
            child: Text(host.displayName),
          ),
        )
        .toList();

    final currentValue =
        _targetHost ??
        selectedHost?.hostname ??
        (hostItems.isNotEmpty ? hostItems.first.value : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: const InputDecoration(
            labelText: '대상 호스트',
            border: OutlineInputBorder(),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentValue,
              isExpanded: true,
              items: hostItems,
              hint: const Text('호스트 선택'),
              onChanged: (value) => setState(() => _targetHost = value),
            ),
          ),
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
        TextField(
          controller: _timeoutController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '타임아웃 (초, 선택)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _submitting ? null : _submitCommand,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: const Text('실행'),
            ),
            if (_formError != null)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  _formError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCommandFilters(List<TwinHost> hosts) {
    final hostOptions = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(value: null, child: Text('전체 호스트')),
      ...hosts
          .where((host) => !host.isCore)
          .map(
            (host) => DropdownMenuItem<String?>(
              value: host.hostname,
              child: Text(host.displayName),
            ),
          ),
    ];

    final statusOptions = <DropdownMenuItem<CommandStatus?>>[
      const DropdownMenuItem<CommandStatus?>(value: null, child: Text('전체 상태')),
      ...CommandStatus.values.map(
        (status) => DropdownMenuItem<CommandStatus?>(
          value: status,
          child: Text(_statusLabel(status)),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: '호스트 필터',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _filterHostname,
                    isExpanded: true,
                    items: hostOptions,
                    onChanged: (value) {
                      setState(() => _filterHostname = value);
                      _applyFilters();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: '상태',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<CommandStatus?>(
                    value: _filterStatus,
                    isExpanded: true,
                    items: statusOptions,
                    onChanged: (value) {
                      setState(() => _filterStatus = value);
                      _applyFilters();
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            labelText: '명령 검색',
            border: const OutlineInputBorder(),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _applyFilters,
                ),
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _applyFilters();
                  },
                ),
              ],
            ),
          ),
          onSubmitted: (_) => _applyFilters(),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _clearFilters,
            child: const Text('필터 초기화'),
          ),
        ),
      ],
    );
  }

  Widget _buildCommandList() {
    final children = <Widget>[];

    if (_loadingCommands) {
      children.add(const LinearProgressIndicator());
      children.add(const SizedBox(height: 8));
    }

    if (_jobs.isEmpty) {
      children.add(
        const Text(
          '전송된 명령이 없습니다.',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      );
    } else {
      children.addAll(
        _jobs.map((job) {
          final color = _statusColor(job.status);
          final duration = job.duration;
          String subtitle = '${job.hostname} · ${job.requestedLabel}';
          if (duration != null) {
            subtitle += ' · ${duration.inSeconds}s';
          }
          if (job.exitCode != null) {
            subtitle += ' · exit ${job.exitCode}';
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1A1F2B)),
              color: const Color(0xFF0D131E),
            ),
            child: ExpansionTile(
              title: Text(
                job.command,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                subtitle,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              trailing: Chip(
                backgroundColor: color.withValues(alpha: 0.15),
                side: BorderSide.none,
                label: Text(
                  job.statusLabel,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
              children: [
                if (job.stdout != null && job.stdout!.isNotEmpty)
                  _CommandOutputBlock(label: 'STDOUT', body: job.stdout!),
                if (job.stderr != null && job.stderr!.isNotEmpty)
                  _CommandOutputBlock(label: 'STDERR', body: job.stderr!),
              ],
            ),
          );
        }),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  String _statusLabel(CommandStatus status) {
    switch (status) {
      case CommandStatus.pending:
        return '대기 중';
      case CommandStatus.running:
        return '실행 중';
      case CommandStatus.succeeded:
        return '성공';
      case CommandStatus.failed:
        return '실패';
      case CommandStatus.timeout:
        return '시간 초과';
    }
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
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.label,
    required this.isActive,
    this.onPressed,
    this.isEnabled = true,
  });

  final String label;
  final bool isActive;
  final VoidCallback? onPressed;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    final bool enabled = isEnabled && onPressed != null;
    final Color baseColor = isActive
        ? Colors.tealAccent
        : const Color(0xFF1A1F2B);
    final Color textColor = isActive
        ? Colors.white
        : enabled
        ? Colors.white70
        : Colors.white24;

    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: textColor,
        side: BorderSide(
          color: baseColor.withValues(alpha: isActive ? 1 : 0.6),
        ),
        backgroundColor: isActive
            ? const Color(0xFF124559)
            : const Color(0xFF0A101A),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: enabled ? onPressed : null,
      child: Align(alignment: Alignment.centerLeft, child: Text(label)),
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

    return AnimatedSlide(
      offset: host == null ? const Offset(0.3, 0) : Offset.zero,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: host == null ? 0 : 1,
        duration: const Duration(milliseconds: 240),
        child: host == null
            ? const SizedBox.shrink()
            : _HostOverlayCard(host: host, samples: samples),
      ),
    );
  }
}

class _HostOverlayCard extends StatelessWidget {
  const _HostOverlayCard({required this.host, required this.samples});

  final TwinHost host;
  final List<_MetricSample> samples;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return SizedBox(
      width: 420,
      height: 560,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OverlayHeader(host: host, theme: theme),
                  const SizedBox(height: 12),
                  _HostQuickStats(host: host),
                  const SizedBox(height: 12),
                  _RealtimeTelemetryCard(
                    host: host,
                    samples: samples,
                    dense: true,
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: _DiagnosticsDeck(host: host)),
                ],
              ),
            ),
          ),
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

class _HostQuickStats extends StatelessWidget {
  const _HostQuickStats({required this.host});

  final TwinHost host;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _MiniMetric(
        label: '업타임',
        value: _formatDuration(host.uptime),
        caption: host.lastSeen.toLocal().toIso8601String(),
      ),
      _MiniMetric(
        label: '네트워크',
        value: host.metrics.netThroughputGbps != null
            ? '${host.metrics.netThroughputGbps!.toStringAsFixed(2)} Gbps'
            : 'N/A',
        caption: host.metrics.netCapacityGbps != null
            ? '용량 ${host.metrics.netCapacityGbps!.toStringAsFixed(1)} Gbps'
            : '용량 정보 없음',
      ),
      _MiniMetric(
        label: '온도',
        value: host.cpuTemperature != null
            ? '${host.cpuTemperature!.toStringAsFixed(1)}℃'
            : (host.gpuTemperature != null
                  ? '${host.gpuTemperature!.toStringAsFixed(1)}℃'
                  : 'N/A'),
        caption: host.cpuTemperature != null ? 'CPU 센서' : 'GPU/센서 기준',
      ),
    ];

    return Row(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          Expanded(child: cards[i]),
          if (i != cards.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value, this.caption});

  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return _GlassTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                caption!,
                style: const TextStyle(color: Colors.white30, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}

class _DiagnosticsDeck extends StatelessWidget {
  const _DiagnosticsDeck({required this.host});

  final TwinHost host;

  @override
  Widget build(BuildContext context) {
    final diagnostics = host.diagnostics;
    final processes = diagnostics.topProcesses.take(4).toList(growable: false);
    final disks = diagnostics.disks.take(2).toList(growable: false);
    final interfaces = diagnostics.interfaces.take(3).toList(growable: false);

    return Row(
      children: [
        Expanded(
          child: _GlassTile(
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
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: _GlassTile(
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
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _GlassTile(
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
                ),
              ),
            ],
          ),
        ),
      ],
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
  const _RealtimeTelemetryCard({
    required this.host,
    required this.samples,
    this.dense = false,
  });

  final TwinHost host;
  final List<_MetricSample> samples;
  final bool dense;

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

    final gaugeSize = dense ? 120.0 : 140.0;
    final padding = dense ? const EdgeInsets.all(16) : const EdgeInsets.all(18);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: dense ? const Color(0x19050B15) : const Color(0xFF050B15),
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
                  subtitle: dense ? null : '업타임 $uptimeText',
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
          SizedBox(height: dense ? 12 : 16),
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
          SizedBox(height: dense ? 10 : 12),
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
          SizedBox(height: dense ? 12 : 16),
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

class _CommandOutputBlock extends StatelessWidget {
  const _CommandOutputBlock({required this.label, required this.body});

  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A131F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1F2A3A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body.trim().isEmpty ? '(출력 없음)' : body.trim(),
            style: const TextStyle(
              color: Colors.white60,
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _TwinScenePainter extends CustomPainter {
  _TwinScenePainter(
    this.frame, {
    required this.mode,
    required this.selectedHost,
    required this.heatMax,
    required this.cameraFocus,
  });

  final TwinStateFrame frame;
  final TwinViewportMode mode;
  final String? selectedHost;
  final double heatMax;
  final TwinPosition cameraFocus;

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

      final double utilization = link.utilization.clamp(0.0, 1.0).toDouble();
      final color = Color.lerp(
        Colors.tealAccent,
        Colors.deepOrangeAccent,
        utilization,
      )!;

      final paint = Paint()
        ..color = color.withValues(alpha: 0.65)
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
    }
  }

  @override
  bool shouldRepaint(covariant _TwinScenePainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.mode != mode ||
      oldDelegate.selectedHost != selectedHost ||
      oldDelegate.heatMax != heatMax ||
      oldDelegate.cameraFocus != cameraFocus;
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
