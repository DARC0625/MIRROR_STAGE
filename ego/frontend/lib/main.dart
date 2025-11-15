import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

/*
 * MIRROR STAGE EGO Frontend
 *
 * 이 파일은 디지털 트윈 HUD 전체를 구성하는 최상위 엔트리 포인트다.
 * - 데이터 스트림: TwinChannel 을 통해 수집한 상태를 `_DigitalTwinShell` 이 구독한다.
 * - 좌/우 사이드바: `_Sidebar`, `_StatusSidebar` 가 4xN 위젯 도킹 시스템을 구성한다.
 * - 메인 스테이지: `_TwinStage` 가 카메라, 팬/줌, 노드 인터랙션과
 *   `_TwinScenePainter` 의 2.5D 투영을 관리한다.
 *
 * OSI 계층 표현, 노드 드래그, 명령 실행 등 대부분의 상호작용 로직이 여기에 모여있다.
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'core/models/command_models.dart';
import 'core/models/twin_models.dart';
import 'core/services/command_service.dart';
import 'core/services/twin_channel.dart';

const double _cameraYaw = -0.45;
const double _cameraPitch = 0.95;
const double _tierHostElevation = 85.0;
const double _tierDepthSpacing = 220.0;
const double _tierPlateSpacing = 110.0;
const double _tierPlatePadding = 160.0;
const List<int> _kDefaultOsiLayers = [1, 2, 3, 4, 5, 6, 7];
const List<Color> _kTierColors = [
  Color(0xFF5EF0FF), // L1
  Color(0xFF47DBFF),
  Color(0xFF35C6FF),
  Color(0xFF2BAEF5),
  Color(0xFF3A8AE8),
  Color(0xFF4F6ED6),
  Color(0xFF5B52C4), // L7
];
const Map<String, int> _kTierKeywordMap = {
  'l1': 1,
  'layer1': 1,
  'physical': 1,
  'phy': 1,
  'access': 1,
  'edge': 1,
  'sensor': 1,
  'l2': 2,
  'layer2': 2,
  'datalink': 2,
  'link': 2,
  'mac': 2,
  'distribution': 2,
  'agg': 2,
  'aggregation': 2,
  'l3': 3,
  'layer3': 3,
  'network': 3,
  'wan': 3,
  'core': 3,
  'routing': 3,
  'ip': 3,
  'l4': 4,
  'layer4': 4,
  'transport': 4,
  'tcp': 4,
  'udp': 4,
  'l5': 5,
  'layer5': 5,
  'session': 5,
  'l6': 6,
  'layer6': 6,
  'presentation': 6,
  'l7': 7,
  'layer7': 7,
  'application': 7,
  'app': 7,
  'service': 7,
};
const double _cameraDistance = 2600.0;

enum TwinViewportMode { topology, heatmap }

enum SidebarWing { left, right }

enum SidebarWidgetType {
  globalMetrics,
  globalLink,
  globalTemperature,
  commandConsole,
  hostLink,
  hostTemperature,
  processes,
  network,
  storage,
}

enum HostDeviceForm { server, switcher, gateway, sensor, client }

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

/// MIRROR STAGE의 메인 셸. 백엔드 채널을 주입받아 전체 UI를 그린다.
class DigitalTwinShell extends StatefulWidget {
  const DigitalTwinShell({super.key, this.channel});

  final TwinChannel? channel;

  @override
  State<DigitalTwinShell> createState() => _DigitalTwinShellState();
}

/// 상태 스트림을 구독하고 사이드바/스테이지/도킹 레이아웃을 제어한다.
class _DigitalTwinShellState extends State<DigitalTwinShell> {
  late final TwinChannel _channel;
  late final bool _ownsChannel;
  late final Stream<TwinStateFrame> _stream;
  TwinStateFrame? _lastFrame;
  final TwinViewportMode _viewportMode = TwinViewportMode.topology;
  String? _selectedHostName;
  late final _WidgetDockController _dockController;
  bool _showWidgetPalette = false;
  int? _focusedTier;
  final Map<String, int> _tierOverrides = {};
  final Map<String, HostDeviceForm> _formOverrides = {};
  final Map<String, String> _iconOverrides = {};

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
        final tierAssignments = _resolveTierAssignments(frame);
        final layoutOverrides = _buildLayoutOverrides(frame, tierAssignments);
        final tierOptions = List<int>.from(_kDefaultOsiLayers);

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
                      tierAssignments: tierAssignments,
                      layoutPositions: layoutOverrides,
                      focusedTier: _focusedTier,
                      iconOverrides: _iconOverrides,
                      formOverrides: _formOverrides,
                      onTierFocusChanged: _setTierFocus,
                      onClearTierFocus: () => _setTierFocus(null),
                      onMoveHostToTier: _moveHostToTier,
                      onEditDevice: _handleDeviceEdit,
                      tierPalette: tierOptions.toSet(),
                    );
                    final leftPanel = _Sidebar(
                      frame: frame,
                      selectedHost: selectedHost,
                      controller: _dockController,
                      wing: SidebarWing.left,
                      paletteOpen: _showWidgetPalette,
                      onTogglePalette: _togglePalette,
                      focusedTier: _focusedTier,
                      tierOptions: tierOptions,
                      onTierFocus: _setTierFocus,
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

  void _setTierFocus(int? tier) {
    if (_focusedTier == tier) return;
    setState(() => _focusedTier = tier);
  }

  /// 호스트별로 적용된 OSI 계층 번호를 계산한다.
  Map<String, int> _resolveTierAssignments(TwinStateFrame frame) {
    final result = <String, int>{};
    for (final host in frame.hosts) {
      final assigned =
          _tierOverrides[host.hostname] ?? _resolveNetworkTier(host);
      result[host.hostname] = _tierLevel(assigned);
    }
    return result;
  }

  /// 각 OSI 계층 단위로 호스트를 정렬해 카메라 프레이밍 안에 담는다.
  Map<String, TwinPosition> _buildLayoutOverrides(
    TwinStateFrame frame,
    Map<String, int> tierAssignments,
  ) {
    const maxTierWidth = 540.0;
    const minSpacing = 160.0;
    const depthSpacing = _tierDepthSpacing;
    final groups = <int, List<TwinHost>>{};
    for (final host in frame.hosts) {
      final tier = tierAssignments[host.hostname] ?? 0;
      groups.putIfAbsent(tier, () => []).add(host);
    }
    final overrides = <String, TwinPosition>{};
    for (final entry in groups.entries) {
      final tier = entry.key;
      final hosts = entry.value
        ..sort((a, b) => a.hostname.compareTo(b.hostname));
      if (hosts.isEmpty) continue;
      final span = math.max(1, hosts.length - 1);
      final width = hosts.length <= 1
          ? 0.0
          : math.min(maxTierWidth, span * minSpacing);
      final startX = hosts.length <= 1 ? 0.0 : -width / 2;
      final step = hosts.length <= 1 ? 0.0 : width / span;
      final tierLevel = _tierLevel(tier);
      final planeIndex = tierLevel - 1;
      for (var i = 0; i < hosts.length; i++) {
        final offsetX = hosts.length <= 1 ? 0.0 : startX + i * step;
        overrides[hosts[i].hostname] = TwinPosition(
          x: offsetX,
          y: planeIndex * _tierHostElevation,
          z: planeIndex * depthSpacing,
        );
      }
    }
    return overrides;
  }

  void _handleDeviceEdit(
    String hostname,
    HostDeviceForm form,
    String? iconPath,
  ) {
    setState(() {
      _formOverrides[hostname] = form;
      final trimmed = iconPath?.trim();
      if (trimmed == null || trimmed.isEmpty) {
        _iconOverrides.remove(hostname);
      } else {
        _iconOverrides[hostname] = trimmed;
      }
    });
  }

  void _moveHostToTier(String hostname, int tier) {
    final normalized = tier.clamp(1, _kDefaultOsiLayers.length);
    setState(() {
      _tierOverrides[hostname] = normalized;
    });
  }
}

/// 좌측 HUD 패널. 위젯 도킹과 계층 필터를 제공한다.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.frame,
    required this.selectedHost,
    required this.controller,
    required this.wing,
    required this.paletteOpen,
    required this.onTogglePalette,
    required this.focusedTier,
    required this.tierOptions,
    required this.onTierFocus,
  });

  final TwinStateFrame frame;
  final TwinHost? selectedHost;
  final _WidgetDockController controller;
  final SidebarWing wing;
  final bool paletteOpen;
  final VoidCallback onTogglePalette;
  final int? focusedTier;
  final List<int> tierOptions;
  final ValueChanged<int?> onTierFocus;

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
              const SizedBox(width: 8),
              _TierButton(
                focusedTier: focusedTier,
                tiers: tierOptions,
                onChanged: onTierFocus,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
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

/// 우측 HUD 패널. 선택한 노드의 실시간 위젯과 히스토리를 도킹한다.
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

/// CustomPaint 기반 투영 위젯. 3D 포인트를 화면 좌표로 사상한다.
class _TwinViewport extends StatelessWidget {
  const _TwinViewport({
    required this.frame,
    required this.height,
    required this.mode,
    required this.selectedHost,
    required this.heatMax,
    required this.onSelectHost,
    required this.onClearSelection,
    required this.onClearTierFocus,
    required this.cameraFrom,
    required this.cameraTo,
    required this.cameraAnimation,
    required this.linkPulse,
    required this.repaint,
    required this.tierAssignments,
    required this.layoutPositions,
    required this.focusedTier,
    required this.iconOverrides,
    required this.formOverrides,
    required this.onRequestEditDevice,
    required this.panOffset,
    required this.zoom,
    required this.tierPalette,
  });

  final TwinStateFrame frame;
  final double height;
  final TwinViewportMode mode;
  final String? selectedHost;
  final double heatMax;
  final ValueChanged<String> onSelectHost;
  final VoidCallback onClearSelection;
  final VoidCallback onClearTierFocus;
  final TwinPosition cameraFrom;
  final TwinPosition cameraTo;
  final Animation<double> cameraAnimation;
  final ValueListenable<double> linkPulse;
  final Listenable repaint;
  final Map<String, int> tierAssignments;
  final Map<String, TwinPosition> layoutPositions;
  final int? focusedTier;
  final Map<String, String> iconOverrides;
  final Map<String, HostDeviceForm> formOverrides;
  final void Function(TwinHost host) onRequestEditDevice;
  final Offset panOffset;
  final double zoom;
  final Set<int> tierPalette;

  TwinPosition get _cameraFocus => TwinPosition.lerp(
    cameraFrom,
    cameraTo,
    Curves.easeOutCubic.transform(cameraAnimation.value),
  );

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
              final center = size.center(Offset.zero) - panOffset;
              final scale =
                  twinScaleFactor(
                    frame,
                    size,
                    layoutOverrides: layoutPositions,
                  ) *
                  zoom;
              final focus = _cameraFocus;
              final projectionMap = <TwinHost, _ProjectedPoint>{
                for (final host in frame.hosts)
                  host: _projectPoint3d(
                    layoutPositions[host.hostname] ?? host.position,
                    center,
                    scale,
                    focus,
                  ),
              };
              final selectedHostModel = selectedHost != null
                  ? frame.hostByName(selectedHost!)
                  : null;
              Widget? holoCard;
              if (selectedHostModel != null) {
                final anchor = projectionMap[selectedHostModel]?.offset;
                if (anchor != null) {
                  const cardSize = Size(320, 200);
                  final showRight = anchor.dx < size.width * 0.5;
                  final horizontalOffset = 24.0;
                  final desiredLeft = showRight
                      ? anchor.dx + horizontalOffset
                      : anchor.dx - cardSize.width - horizontalOffset;
                  final clampedLeft = desiredLeft.clamp(
                    8.0,
                    size.width - cardSize.width - 8.0,
                  );
                  final clampedTop = (anchor.dy - cardSize.height * 0.5).clamp(
                    8.0,
                    size.height - cardSize.height - 8.0,
                  );
                  holoCard = Positioned(
                    left: clampedLeft,
                    top: clampedTop,
                    width: cardSize.width,
                    child: _HostHoloCard(
                      host: selectedHostModel,
                      preferRight: showRight,
                      formOverride: formOverrides[selectedHostModel.hostname],
                      iconPath:
                          iconOverrides[selectedHostModel.hostname] ??
                          selectedHostModel.diagnostics.tags['icon'],
                      onEdit: () => onRequestEditDevice(selectedHostModel),
                    ),
                  );
                }
              }

              final markerWidgets = projectionMap.entries.map((entry) {
                final host = entry.key;
                final projection = entry.value;
                final tier = tierAssignments[host.hostname];
                final normalizedTier = _tierLevel(
                  tier ?? _resolveNetworkTier(host),
                );
                final highlighted =
                    focusedTier == null || focusedTier == normalizedTier;
                final iconPath =
                    iconOverrides[host.hostname] ??
                    host.diagnostics.tags['icon'] ??
                    host.diagnostics.tags['iconPath'];
                final form =
                    formOverrides[host.hostname] ?? _resolveDeviceForm(host);
                Widget buildMarker(double opacityFactor) => Opacity(
                  opacity: (highlighted ? 1 : 0.25) * opacityFactor,
                  child: Transform.scale(
                    scale: projection.scaleFactor.clamp(0.7, 1.2),
                    origin: const Offset(0, 0),
                    child: _DeviceIconMarker(assetPath: iconPath, form: form),
                  ),
                );
                final idleMarker = buildMarker(1);
                return Positioned(
                  left: projection.offset.dx - 20,
                  top: projection.offset.dy - 20,
                  child: LongPressDraggable<_TierDragPayload>(
                    data: _TierDragPayload(
                      hostname: host.hostname,
                      fromTier: normalizedTier,
                    ),
                    dragAnchorStrategy: pointerDragAnchorStrategy,
                    feedback: Material(
                      color: Colors.transparent,
                      child: buildMarker(1),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.2,
                      child: buildMarker(1),
                    ),
                    child: GestureDetector(
                      onTap: () => onSelectHost(host.hostname),
                      child: idleMarker,
                    ),
                  ),
                );
              }).toList();

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) {
                      final tap = details.localPosition;
                      TwinHost? nearest;
                      double minDistance = double.infinity;
                      projectionMap.forEach((host, projection) {
                        final radius = hostBubbleRadius(host);
                        final distance = (tap - projection.offset).distance;
                        if (distance <= radius + 18 && distance < minDistance) {
                          nearest = host;
                          minDistance = distance;
                        }
                      });
                      if (nearest != null) {
                        onSelectHost(nearest!.hostname);
                      } else {
                        onClearSelection();
                        onClearTierFocus();
                      }
                    },
                    child: RepaintBoundary(
                      child: CustomPaint(
                        isComplex: true,
                        willChange: true,
                        painter: _TwinScenePainter(
                          frame,
                          mode: mode,
                          selectedHost: selectedHost,
                          heatMax: heatMax,
                          cameraFrom: cameraFrom,
                          cameraTo: cameraTo,
                          cameraAnimation: cameraAnimation,
                          linkPulse: linkPulse,
                          repaint: repaint,
                          projections: {
                            for (final entry in projectionMap.entries)
                              entry.key.hostname: entry.value,
                          },
                          tierAssignments: tierAssignments,
                          focusedTier: focusedTier,
                          layoutPositions: layoutPositions,
                          formOverrides: formOverrides,
                          tierPalette: tierPalette,
                          sceneCenter: center,
                          sceneScale: scale,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                  ...markerWidgets,
                  if (holoCard != null) holoCard,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 팬/줌 카메라와 노드 인터랙션을 담당하는 메인 스테이지.
class _TwinStage extends StatefulWidget {
  const _TwinStage({
    required this.frame,
    required this.mode,
    required this.selectedHost,
    required this.heatMax,
    required this.onSelectHost,
    required this.onClearSelection,
    required this.tierAssignments,
    required this.layoutPositions,
    required this.focusedTier,
    required this.iconOverrides,
    required this.formOverrides,
    required this.onTierFocusChanged,
    required this.onClearTierFocus,
    required this.onEditDevice,
    required this.onMoveHostToTier,
    required this.tierPalette,
  });

  final TwinStateFrame frame;
  final TwinViewportMode mode;
  final TwinHost? selectedHost;
  final double heatMax;
  final ValueChanged<String> onSelectHost;
  final VoidCallback onClearSelection;
  final Map<String, int> tierAssignments;
  final Map<String, TwinPosition> layoutPositions;
  final int? focusedTier;
  final Map<String, String> iconOverrides;
  final Map<String, HostDeviceForm> formOverrides;
  final ValueChanged<int?> onTierFocusChanged;
  final VoidCallback onClearTierFocus;
  final void Function(String hostname, int tier) onMoveHostToTier;
  final void Function(String hostname, HostDeviceForm form, String? iconPath)
  onEditDevice;
  final Set<int> tierPalette;

  @override
  State<_TwinStage> createState() => _TwinStageState();
}

/// 팬/줌/카메라 인터랙션에 대한 상태 로직.
class _TwinStageState extends State<_TwinStage> with TickerProviderStateMixin {
  late final AnimationController _cameraController;
  late final ValueNotifier<double> _linkPulseValue;
  late final Listenable _stageTicker;
  Timer? _linkPulseTimer;
  double _linkPhase = 0;
  TwinPosition _cameraFrom = TwinPosition.zero;
  TwinPosition _cameraTo = TwinPosition.zero;
  Offset _panOffset = Offset.zero;
  Offset _panStart = Offset.zero;
  Offset _focalStart = Offset.zero;
  double _zoom = 1.0;
  double _zoomStart = 1.0;
  Size? _viewportSize;

  @override
  void initState() {
    super.initState();
    _cameraController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..value = 1;
    _cameraTo = widget.selectedHost?.position ?? _sceneCentroid();
    _cameraFrom = _cameraTo;

    _linkPulseValue = ValueNotifier<double>(0);
    _linkPulseTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      _linkPhase += 0.045;
      if (_linkPhase > 1) {
        _linkPhase -= 1;
      }
      final eased = 0.5 - 0.5 * math.cos(_linkPhase * math.pi * 2);
      _linkPulseValue.value = eased;
    });
    _stageTicker = Listenable.merge([_cameraController, _linkPulseValue]);
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
    _linkPulseTimer?.cancel();
    _linkPulseValue.dispose();
    super.dispose();
  }

  void _retargetCamera(TwinPosition? target) {
    _cameraFrom = _currentCameraFocus;
    _cameraTo = target ?? _sceneCentroid();
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

  /// 현재 배치된 모든 호스트의 중심점을 계산한다.
  TwinPosition _sceneCentroid() {
    if (widget.layoutPositions.isEmpty) {
      return TwinPosition.zero;
    }
    double sumX = 0;
    double sumY = 0;
    double sumZ = 0;
    for (final position in widget.layoutPositions.values) {
      sumX += position.x;
      sumY += position.y;
      sumZ += position.z;
    }
    final count = widget.layoutPositions.length.toDouble();
    return TwinPosition(x: sumX / count, y: sumY / count, z: sumZ / count);
  }

  /// 뷰포트 밖으로 나가지 않도록 팬 오프셋을 제한한다.
  Offset _clampPan(Offset candidate) {
    final size = _viewportSize;
    if (size == null) return candidate;
    final limitX = size.width * 0.35;
    final limitY = size.height * 0.35;
    return Offset(
      candidate.dx.clamp(-limitX, limitX),
      candidate.dy.clamp(-limitY, limitY),
    );
  }

  @override
  /// 팬/줌 제스처와 도크를 포함한 전체 스테이지를 렌더링한다.
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        _panOffset = _clampPan(_panOffset);
        final hostRail = Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: RepaintBoundary(
              child: _HostChipRail(
                hosts: widget.frame.hosts,
                selectedHost: widget.selectedHost?.hostname,
                onSelect: widget.onSelectHost,
              ),
            ),
          ),
        );

        return Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              setState(() {
                _zoom = (_zoom - event.scrollDelta.dy * 0.001).clamp(0.6, 2.5);
                _panOffset = _clampPan(_panOffset);
              });
            }
          },
          child: GestureDetector(
            onScaleStart: (details) {
              _panStart = _panOffset;
              _zoomStart = _zoom;
              _focalStart = details.focalPoint;
            },
            onScaleUpdate: (details) {
              setState(() {
                _zoom = (_zoomStart * details.scale).clamp(0.6, 2.5);
                final delta = details.focalPoint - _focalStart;
                _panOffset = _clampPan(_panStart + delta);
              });
            },
            child: Stack(
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
                    onClearTierFocus: widget.onClearTierFocus,
                    cameraFrom: _cameraFrom,
                    cameraTo: _cameraTo,
                    cameraAnimation: _cameraController,
                    linkPulse: _linkPulseValue,
                    repaint: _stageTicker,
                    tierAssignments: widget.tierAssignments,
                    layoutPositions: widget.layoutPositions,
                    focusedTier: widget.focusedTier,
                    iconOverrides: widget.iconOverrides,
                    formOverrides: widget.formOverrides,
                    onRequestEditDevice: _handleEditRequest,
                    panOffset: _panOffset,
                    zoom: _zoom,
                    tierPalette: widget.tierPalette,
                  ),
                ),
                Positioned(
                  top: 24,
                  left: 24,
                  child: _TierDock(
                    tiers: _kDefaultOsiLayers,
                    focusedTier: widget.focusedTier,
                    onFocusTier: widget.onTierFocusChanged,
                    onDrop: widget.onMoveHostToTier,
                  ),
                ),
                hostRail,
              ],
            ),
          ),
        );
      },
    );
  }

  /// 호스트 편집 모달을 띄워 폼/아이콘을 수정한다.
  void _handleEditRequest(TwinHost host) {
    final currentForm =
        widget.formOverrides[host.hostname] ?? _resolveDeviceForm(host);
    final currentIcon =
        widget.iconOverrides[host.hostname] ?? host.diagnostics.tags['icon'];
    var selectedForm = currentForm;
    final controller = TextEditingController(text: currentIcon ?? '');
    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0B121D),
              title: Text('${host.displayName} 장비 편집'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('장비 유형'),
                  const SizedBox(height: 6),
                  DropdownButton<HostDeviceForm>(
                    value: selectedForm,
                    items: HostDeviceForm.values
                        .map(
                          (form) => DropdownMenuItem(
                            value: form,
                            child: Text(_formLabel(form)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setModalState(() {
                        selectedForm = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('아이콘 에셋 경로'),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: 'assets/device_icons/server.png',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: () {
                    widget.onEditDevice(
                      host.hostname,
                      selectedForm,
                      controller.text,
                    );
                    Navigator.pop(context);
                  },
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) => controller.dispose());
  }
}

/// CPU/메모리 등의 아날로그 게이지 위젯.
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

/// 게이지 애니메이션 로직을 담당하는 상태 클래스.
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

/// 게이지 원호를 직접 그리는 Painter.
class _GaugePainter extends CustomPainter {
  const _GaugePainter({required this.normalized, required this.color});

  final double normalized;
  final Color color;

  @override
  /// 전체 장면(바닥, 계층, 링크, 호스트)을 순서대로 그린다.
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

/// 좌측 패널 상단에 보여주는 전역/호스트 메트릭 카드.
class _SidebarOverviewCard extends StatelessWidget {
  const _SidebarOverviewCard({
    required this.frame,
    required this.gaugeSize,
    this.focusHost,
  });

  final TwinStateFrame frame;
  final double gaugeSize;
  final TwinHost? focusHost;

  @override
  Widget build(BuildContext context) {
    final host = focusHost;
    final isHostView = host != null;
    final headerLabel = host?.displayName ?? '전역 메트릭';
    final cpuValue = (host?.metrics.cpuLoad ?? frame.averageCpuLoad)
        .clamp(0, 100)
        .toDouble();
    final memValue =
        (host?.metrics.memoryUsedPercent ?? frame.memoryUtilizationPercent)
            .clamp(0, 100)
            .toDouble();

    final cpuSubtitle = host != null
        ? '업타임 ${_formatDuration(host.uptime)}'
        : (frame.averageCpuTemperature > 0
              ? '온도 ${frame.averageCpuTemperature.toStringAsFixed(1)}℃'
              : null);
    final memSubtitle = host != null ? _formatHostMemorySubtitle(host) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          headerLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _AnalogGauge(
                  label: isHostView ? 'CPU 사용률' : '평균 CPU',
                  value: cpuValue,
                  maxValue: 100,
                  units: '%',
                  decimals: 1,
                  subtitle: cpuSubtitle,
                  startColor: Colors.lightBlueAccent,
                  endColor: Colors.deepOrangeAccent,
                  size: gaugeSize,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AnalogGauge(
                  label: '메모리',
                  value: memValue,
                  maxValue: 100,
                  units: '%',
                  decimals: 1,
                  subtitle: memSubtitle,
                  startColor: const Color(0xFF38BDF8),
                  endColor: Colors.pinkAccent,
                  size: gaugeSize,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 좌측 패널에서 원격 명령을 실행할 수 있는 카드.
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = constraints.maxHeight < 360;
        final controlHeight = dense ? 34.0 : 42.0;
        final labelWidth = dense ? 60.0 : 72.0;
        final gap = dense ? 4.0 : 6.0;
        final fieldTextStyle = TextStyle(
          color: Colors.white,
          fontSize: dense ? 12 : 13,
        );
        final labelStyle = TextStyle(
          color: Colors.white54,
          fontSize: dense ? 11 : 12,
          fontWeight: FontWeight.w600,
        );
        final decoration = BoxDecoration(
          color: const Color(0x220C1A2A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x221B2333)),
        );

        Widget fieldShell(Widget child) =>
            DecoratedBox(decoration: decoration, child: child);

        Widget dropdownField() => fieldShell(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedHostname ?? hostItems.first.value,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
                dropdownColor: const Color(0xFF0C1424),
                style: fieldTextStyle,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedHostname = value;
                    _formError = null;
                  });
                },
                items: hostItems,
              ),
            ),
          ),
        );

        Widget textField(
          TextEditingController controller, {
          String? hint,
          TextInputType? keyboardType,
        }) => fieldShell(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              style: fieldTextStyle,
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: hint,
                hintStyle: fieldTextStyle.copyWith(color: Colors.white38),
              ),
            ),
          ),
        );

        Widget fieldRow(String label, Widget child) => SizedBox(
          height: controlHeight,
          child: Row(
            children: [
              SizedBox(
                width: labelWidth,
                child: Text(label, style: labelStyle),
              ),
              const SizedBox(width: 8),
              Expanded(child: SizedBox.expand(child: child)),
            ],
          ),
        );

        final buttonWidth = dense ? 74.0 : 90.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '원격 자동화',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            SizedBox(height: gap),
            fieldRow('노드', dropdownField()),
            SizedBox(height: gap),
            fieldRow(
              '명령',
              textField(_commandController, hint: '예) ipconfig /all'),
            ),
            SizedBox(height: gap),
            fieldRow(
              '타임아웃',
              Row(
                children: [
                  Expanded(
                    child: SizedBox.expand(
                      child: textField(
                        _timeoutController,
                        hint: '초',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: buttonWidth,
                    height: double.infinity,
                    child: ElevatedButton(
                      onPressed: _sending ? null : _submitCommand,
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        textStyle: fieldTextStyle.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('실행'),
                    ),
                  ),
                ],
              ),
            ),
            if (_formError != null)
              Padding(
                padding: EdgeInsets.only(top: gap),
                child: Text(
                  _formError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                ),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            SizedBox(height: gap),
            Expanded(
              child: visibleJobs.isEmpty
                  ? const Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        '명령 기록이 없습니다.',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    )
                  : ListView.separated(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: visibleJobs.length,
                      separatorBuilder: (_, __) => SizedBox(height: gap),
                      itemBuilder: (context, index) => _CommandJobTile(
                        color: _statusColor(visibleJobs[index].status),
                        job: visibleJobs[index],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// 명령 실행 이력 한 줄 UI.
class _CommandJobTile extends StatelessWidget {
  const _CommandJobTile({required this.color, required this.job});

  final Color color;
  final CommandJob job;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  job.statusLabel,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${job.hostname} · ${job.requestedLabel}',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

/// 작은 상태 라벨 형태의 피ill 위젯.
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
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// 하단 노드 선택 슬라이더.
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

/// 단일 호스트 선택 칩.
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
    final throughputGbps = host.metrics.netThroughputGbps;

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
                    maxLines: 1,
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (throughputGbps != null && throughputGbps > 0)
              Text(
                _formatThroughputLabel(throughputGbps),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.tealAccent, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}

/// 선택한 호스트 정보를 보여주는 홀로그램 카드.
class _HostHoloCard extends StatelessWidget {
  const _HostHoloCard({
    required this.host,
    required this.preferRight,
    this.formOverride,
    this.iconPath,
    this.onEdit,
  });

  final TwinHost host;
  final bool preferRight;
  final HostDeviceForm? formOverride;
  final String? iconPath;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (host.status) {
      TwinHostStatus.online => Colors.tealAccent,
      TwinHostStatus.stale => Colors.amberAccent,
      TwinHostStatus.offline => Colors.redAccent,
    };
    final statusLabel = switch (host.status) {
      TwinHostStatus.online => 'ONLINE',
      TwinHostStatus.stale => 'DEGRADED',
      TwinHostStatus.offline => 'OFFLINE',
    };
    final osLabel = host.osDisplay.isNotEmpty ? host.osDisplay : host.platform;
    final uptime = _formatDuration(host.uptime);
    final rack = host.rack ?? 'UNASSIGNED';
    final deviceLabel = _formLabel(formOverride ?? _resolveDeviceForm(host));

    final highlightBegin = preferRight ? Alignment.topLeft : Alignment.topRight;
    final highlightEnd = preferRight
        ? Alignment.bottomRight
        : Alignment.bottomLeft;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xF006101C),
        gradient: LinearGradient(
          colors: [Colors.white.withValues(alpha: 0.04), Colors.transparent],
          begin: highlightBegin,
          end: highlightEnd,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.tealAccent.withValues(alpha: 0.22),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  host.displayName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: statusColor.withValues(alpha: 0.2),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onEdit != null)
                IconButton(
                  tooltip: '장비 수정',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: 16),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            osLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Text(
            'HARDWARE',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _HoloDatum(
                icon: Icons.devices_other,
                label: '타입',
                value: deviceLabel,
              ),
              _HoloDatum(
                icon: Icons.memory,
                label: 'CPU',
                value: host.cpuSummary,
              ),
              _HoloDatum(
                icon: Icons.toc,
                label: '코어',
                value:
                    '${host.hardware.cpuPhysicalCores ?? '-'}P / ${host.hardware.cpuLogicalCores ?? '-'}T',
              ),
              _HoloDatum(
                icon: Icons.sd_storage,
                label: '메모리',
                value: _formatCapacity(host.memoryTotalBytes),
              ),
              _HoloDatum(
                icon: Icons.computer,
                label: 'GPU',
                value:
                    host.diagnostics.tags['gpuModel'] ??
                    host.diagnostics.tags['gpu'] ??
                    '정보 없음',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'INFRASTRUCTURE',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _HoloDatum(icon: Icons.public, label: 'IP', value: host.ip),
              _HoloDatum(
                icon: Icons.router,
                label: 'NIC',
                value: _formatInterfaceSummary(host.diagnostics.interfaces),
              ),
              if (iconPath != null)
                _HoloDatum(icon: Icons.image, label: '아이콘', value: iconPath!),
              _HoloDatum(
                icon: Icons.storage,
                label: '스토리지',
                value: _summarizeDisks(host.diagnostics.disks),
              ),
              _HoloDatum(icon: Icons.access_time, label: '업타임', value: uptime),
              _HoloDatum(
                icon: Icons.terminal,
                label: 'Agent',
                value: host.agentVersion,
              ),
              _HoloDatum(icon: Icons.hub, label: 'Rack', value: rack),
            ],
          ),
        ],
      ),
    );
  }
}

/// 홀로카드 안의 작은 데이터 셀.
class _HoloDatum extends StatelessWidget {
  const _HoloDatum({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x331B2333)),
        color: const Color(0x44080E17),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white60),
          const SizedBox(width: 6),
          Text(
            '$label ',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 최근 일정량의 메트릭 샘플을 보존하는 순환 버퍼.
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

/// 버퍼 내부 샘플 표현.
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

/// 링크, 노드, 계층 판을 한번에 그리는 핵심 CustomPainter.
/// 링크, 노드, 계층 판을 한번에 그리는 핵심 CustomPainter.
class _TwinScenePainter extends CustomPainter {
  _TwinScenePainter(
    this.frame, {
    required this.mode,
    required this.selectedHost,
    required this.heatMax,
    required this.cameraFrom,
    required this.cameraTo,
    required this.cameraAnimation,
    required this.linkPulse,
    required this.projections,
    required this.tierAssignments,
    required this.focusedTier,
    required this.layoutPositions,
    required this.formOverrides,
    required this.tierPalette,
    required this.sceneCenter,
    required this.sceneScale,
    super.repaint,
  });

  final TwinStateFrame frame;
  final TwinViewportMode mode;
  final String? selectedHost;
  final double heatMax;
  final TwinPosition cameraFrom;
  final TwinPosition cameraTo;
  final Animation<double> cameraAnimation;
  final ValueListenable<double> linkPulse;
  final Map<String, _ProjectedPoint> projections;
  final Map<String, int> tierAssignments;
  final int? focusedTier;
  final Map<String, TwinPosition> layoutPositions;
  final Map<String, HostDeviceForm> formOverrides;
  final Set<int> tierPalette;
  final Offset sceneCenter;
  final double sceneScale;

  TwinPosition get _cameraFocus => TwinPosition.lerp(
    cameraFrom,
    cameraTo,
    Curves.easeOutCubic.transform(cameraAnimation.value),
  );

  double get _linkPulse => linkPulse.value;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = _computeSceneBounds(layoutPositions, frame);
    _paintGrid(canvas, size, bounds);
    _paintLayers(canvas, bounds, sceneCenter, sceneScale);
    _paintLinks(canvas, size, sceneCenter, sceneScale);
    _paintHosts(canvas, size, sceneCenter, sceneScale);
  }

  /// 바닥 그리드 및 원근감을 그린다.
  void _paintGrid(Canvas canvas, Size size, _SceneBounds bounds) {
    final horizon = size.height * 0.35;
    final skyRect = Rect.fromLTWH(0, 0, size.width, horizon);
    final floorRect = Rect.fromLTWH(
      0,
      horizon,
      size.width,
      size.height - horizon,
    );

    final skyPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF070E18), Color(0xFF0A1524)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(skyRect);
    canvas.drawRect(skyRect, skyPaint);

    final floorPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF051627), Color(0xFF041019)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(floorRect);
    canvas.drawRect(floorRect, floorPaint);

    final plate = _isoPlatePath(
      bounds.minX - _tierPlatePadding * 1.5,
      bounds.maxX + _tierPlatePadding * 1.5,
      bounds.minZ - _tierPlatePadding * 1.5,
      bounds.maxZ + _tierPlatePadding * 1.5,
      -_tierPlateSpacing * 0.6,
      sceneCenter,
      sceneScale,
    );
    final floorPath = Path()..addPolygon(plate, true);
    canvas.drawPath(
      floorPath,
      Paint()
        ..shader = ui.Gradient.linear(plate[0], plate[2], [
          const Color(0xFF041019).withValues(alpha: 0.85),
          const Color(0xFF071828).withValues(alpha: 0.9),
        ]),
    );

    const gridLines = 10;
    for (var i = 0; i <= gridLines; i++) {
      final t = i / gridLines;
      final x = ui.lerpDouble(bounds.minX, bounds.maxX, t)!;
      final start = twinProjectPoint(
        TwinPosition(
          x: x,
          y: -_tierPlateSpacing * 0.6,
          z: bounds.minZ - _tierPlatePadding,
        ),
        sceneCenter,
        sceneScale,
        _cameraFocus,
      );
      final end = twinProjectPoint(
        TwinPosition(
          x: x,
          y: -_tierPlateSpacing * 0.6,
          z: bounds.maxZ + _tierPlatePadding,
        ),
        sceneCenter,
        sceneScale,
        _cameraFocus,
      );
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.03)
          ..strokeWidth = 1.0,
      );
    }
    for (var i = 0; i <= gridLines; i++) {
      final t = i / gridLines;
      final z = ui.lerpDouble(bounds.minZ, bounds.maxZ, t)!;
      final start = twinProjectPoint(
        TwinPosition(
          x: bounds.minX - _tierPlatePadding,
          y: -_tierPlateSpacing * 0.6,
          z: z,
        ),
        sceneCenter,
        sceneScale,
        _cameraFocus,
      );
      final end = twinProjectPoint(
        TwinPosition(
          x: bounds.maxX + _tierPlatePadding,
          y: -_tierPlateSpacing * 0.6,
          z: z,
        ),
        sceneCenter,
        sceneScale,
        _cameraFocus,
      );
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.03)
          ..strokeWidth = 1.0,
      );
    }
  }

  /// OSI 계층 판을 시각화한다.
  void _paintLayers(
    Canvas canvas,
    _SceneBounds bounds,
    Offset center,
    double scale,
  ) {
    final tiers = {..._kDefaultOsiLayers, ...tierPalette}.toList()..sort();
    for (final layer in tiers) {
      final planeIndex = _tierLevel(layer) - 1;
      final altitude = planeIndex * _tierPlateSpacing;
      final thickness = _tierPlateSpacing * 0.65;
      final top = _isoPlatePath(
        bounds.minX - _tierPlatePadding,
        bounds.maxX + _tierPlatePadding,
        bounds.minZ - _tierPlatePadding,
        bounds.maxZ + _tierPlatePadding,
        altitude,
        center,
        scale,
      );
      final bottom = _isoPlatePath(
        bounds.minX - _tierPlatePadding,
        bounds.maxX + _tierPlatePadding,
        bounds.minZ - _tierPlatePadding,
        bounds.maxZ + _tierPlatePadding,
        altitude - thickness,
        center,
        scale,
      );
      final highlighted = focusedTier == null || layer == focusedTier;
      final layerColor = _tierColor(layer);
      final alphaScale = highlighted ? 1.0 : 0.25;
      final topPath = Path()..addPolygon(top, true);
      canvas.drawPath(
        topPath,
        Paint()
          ..color = layerColor.withValues(alpha: 0.06 * alphaScale)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 14),
      );
      final sidePaint = Paint()
        ..color = layerColor.withValues(alpha: 0.04 * alphaScale);
      for (var i = 0; i < top.length; i++) {
        final next = (i + 1) % top.length;
        final face = Path()
          ..moveTo(top[i].dx, top[i].dy)
          ..lineTo(top[next].dx, top[next].dy)
          ..lineTo(bottom[next].dx, bottom[next].dy)
          ..lineTo(bottom[i].dx, bottom[i].dy)
          ..close();
        canvas.drawPath(face, sidePaint);
      }
      canvas.drawPath(
        topPath,
        Paint()
          ..shader = ui.Gradient.linear(top[0], top[2], [
            Colors.white.withValues(alpha: 0.08 * alphaScale),
            layerColor.withValues(alpha: 0.05 * alphaScale),
          ]),
      );
      canvas.drawPath(
        topPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = highlighted ? 1.4 : 0.8
          ..color = layerColor.withValues(alpha: 0.35 * alphaScale),
      );
      final centroidX =
          top.fold<double>(0, (sum, point) => sum + point.dx) / top.length;
      final centroidY =
          top.fold<double>(0, (sum, point) => sum + point.dy) / top.length;
      final labelPainter = TextPainter(
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: 'L$layer',
          style: TextStyle(
            color: Colors.white.withValues(alpha: highlighted ? 1.0 : 0.6),
            fontWeight: FontWeight.w700,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
      )..layout();
      final labelWidth = labelPainter.width + 14;
      final labelHeight = labelPainter.height + 6;
      final labelRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centroidX, centroidY - 18),
          width: labelWidth,
          height: labelHeight,
        ),
        const Radius.circular(12),
      );
      canvas.drawRRect(
        labelRect,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35 * alphaScale)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRRect(
        labelRect,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.45 * alphaScale)
          ..style = PaintingStyle.stroke,
      );
      labelPainter.paint(
        canvas,
        Offset(
          centroidX - labelPainter.width / 2,
          centroidY - 18 - labelPainter.height / 2,
        ),
      );
    }
  }

/// 계층 판의 꼭짓점을 등각 투영 좌표로 변환한다.
List<Offset> _isoPlatePath(
    double minX,
    double maxX,
    double minZ,
    double maxZ,
    double altitude,
    Offset center,
    double scale,
  ) {
    final corners = [
      TwinPosition(x: minX, y: altitude, z: minZ),
      TwinPosition(x: maxX, y: altitude, z: minZ),
      TwinPosition(x: maxX, y: altitude, z: maxZ),
      TwinPosition(x: minX, y: altitude, z: maxZ),
    ];
    return corners
        .map(
          (position) => twinProjectPoint(position, center, scale, _cameraFocus),
        )
        .toList(growable: false);
  }

  /// 호스트 간 링크를 곡선 경로로 그린다.
  void _paintLinks(Canvas canvas, Size size, Offset center, double scale) {
    final hosts = {for (final host in frame.hosts) host.hostname: host};

    for (final link in frame.links) {
      final source = hosts[link.source];
      final target = hosts[link.target];
      if (source == null || target == null) continue;
      final sourceProjection = projections[source.hostname];
      final targetProjection = projections[target.hostname];
      if (sourceProjection == null || targetProjection == null) continue;

      final sourcePoint = sourceProjection.offset;
      final targetPoint = targetProjection.offset;

      final controlPoint = Offset(
        (sourcePoint.dx + targetPoint.dx) / 2,
        math.min(sourcePoint.dy, targetPoint.dy) - 40,
      );

      final capacity = link.capacityGbps ?? 0;
      final measured = link.throughputGbps;
      final utilization = capacity > 0
          ? (measured / capacity).clamp(0.0, 1.0)
          : link.utilization.clamp(0.0, 1.0);
      final pulse = 0.25 + 0.75 * _linkPulse;
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

      final highlight =
          focusedTier == null ||
          focusedTier == tierAssignments[source.hostname] ||
          focusedTier == tierAssignments[target.hostname];
      final opacityScale = highlight ? 1.0 : 0.1;

      final paint = Paint()
        ..shader = ui.Gradient.linear(sourcePoint, targetPoint, [
          color.withValues(alpha: 0.2 * opacityScale),
          color.withValues(alpha: 0.95 * opacityScale),
        ])
        ..strokeWidth = 2 + utilization * 4 + pulse
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(path, paint);

      final metrics = path.computeMetrics();
      for (final metric in metrics) {
        final window = (46 + utilization * 70).clamp(24.0, metric.length * 0.8);
        final forwardOffset =
            (metric.length - window) * (0.1 + _linkPulse * 0.8);
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
            (metric.length - window) * (0.2 + (1 - _linkPulse) * 0.7);
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
      final measuredLabel = _formatThroughputLabel(measured);
      final capacityLabel = capacity > 0
          ? _formatThroughputLabel(capacity)
          : null;
      final bandwidthLabel = capacityLabel != null
          ? '$measuredLabel / $capacityLabel'
          : measuredLabel;
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

  /// 각 호스트 노드를 도형/텍스트로 렌더링한다.
  void _paintHosts(Canvas canvas, Size size, Offset center, double scale) {
    for (final host in frame.hosts) {
      final projection = projections[host.hostname];
      if (projection == null) continue;
      final basePosition = projection.offset;
      final status = host.status;
      final isCore = host.isCore;
      final isSelected = selectedHost != null && selectedHost == host.hostname;
      final tier = tierAssignments[host.hostname];
      final highlighted =
          focusedTier == null || tier == focusedTier || isSelected;
      final opacityScale = highlighted ? 1.0 : 0.2;

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
      final form = formOverrides[host.hostname] ?? _resolveDeviceForm(host);
      _drawDeviceForm(
        canvas: canvas,
        position: basePosition,
        radius: radius,
        height: 20.0 + projection.scaleFactor * 50,
        color: color.withValues(
          alpha: (color.a * opacityScale).clamp(0.0, 1.0),
        ),
        form: form,
        isSelected: isSelected,
      );

      if (host.isDummy && !isCore) {
        final markerPath = Path()
          ..moveTo(basePosition.dx, basePosition.dy - radius - 4)
          ..lineTo(basePosition.dx + 8, basePosition.dy - radius - 16)
          ..lineTo(basePosition.dx - 8, basePosition.dy - radius - 16)
          ..close();
        canvas.drawPath(
          markerPath,
          Paint()
            ..color = Colors.amberAccent.withValues(alpha: 0.8)
            ..style = PaintingStyle.fill,
        );
      }

      if (selectedHost != host.hostname) {
        final labelAnchor = _isoDiamondPoints(basePosition, radius).first;
        final labelText = host.displayName;
        final textPainter = TextPainter(
          text: TextSpan(
            text: labelText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 160);
        textPainter.paint(
          canvas,
          labelAnchor + Offset(-textPainter.width / 2, -textPainter.height - 6),
        );
      }
    }
  }

  void _drawDeviceForm({
    required Canvas canvas,
    required Offset position,
    required double radius,
    required double height,
    required Color color,
    required HostDeviceForm form,
    required bool isSelected,
  }) {
    switch (form) {
      case HostDeviceForm.server:
        _drawServerCube(canvas, position, radius, height, color, isSelected);
        break;
      case HostDeviceForm.switcher:
        _drawSwitchBlade(canvas, position, radius, color, isSelected);
        break;
      case HostDeviceForm.gateway:
        _drawGatewayPrism(canvas, position, radius, color, isSelected);
        break;
      case HostDeviceForm.sensor:
        _drawSensorDisk(canvas, position, radius, color, isSelected);
        break;
      case HostDeviceForm.client:
        _drawClientNode(canvas, position, radius, color, isSelected);
        break;
    }
  }

  void _drawServerCube(
    Canvas canvas,
    Offset position,
    double radius,
    double height,
    Color color,
    bool isSelected,
  ) {
    final topPoints = _isoDiamondPoints(position, radius);
    final rightPaint = Paint()
      ..shader = ui.Gradient.linear(
        topPoints[1],
        topPoints[1] + Offset(0, height),
        [
          color.withValues(alpha: 0.75),
          Colors.blueGrey.withValues(alpha: 0.35),
        ],
      );
    final leftPaint = Paint()
      ..shader = ui.Gradient.linear(
        topPoints[3],
        topPoints[3] + Offset(0, height),
        [
          color.withValues(alpha: 0.55),
          Colors.blueGrey.withValues(alpha: 0.25),
        ],
      );
    final rightFace = Path()
      ..moveTo(topPoints[1].dx, topPoints[1].dy)
      ..lineTo(topPoints[2].dx, topPoints[2].dy)
      ..lineTo(topPoints[2].dx, topPoints[2].dy + height)
      ..lineTo(topPoints[1].dx, topPoints[1].dy + height)
      ..close();
    canvas.drawPath(rightFace, rightPaint);

    final leftFace = Path()
      ..moveTo(topPoints[3].dx, topPoints[3].dy)
      ..lineTo(topPoints[2].dx, topPoints[2].dy)
      ..lineTo(topPoints[2].dx, topPoints[2].dy + height)
      ..lineTo(topPoints[3].dx, topPoints[3].dy + height)
      ..close();
    canvas.drawPath(leftFace, leftPaint);

    final top = Path()..addPolygon(topPoints, true);
    final topPaint = Paint()
      ..shader = ui.Gradient.radial(position, radius * 1.4, [
        Colors.white.withValues(alpha: 0.95),
        color.withValues(alpha: 0.75),
      ]);
    canvas.drawPath(top, topPaint);
    if (isSelected) {
      canvas.drawPath(
        top,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.7),
      );
    }
  }

  void _drawSwitchBlade(
    Canvas canvas,
    Offset position,
    double radius,
    Color color,
    bool isSelected,
  ) {
    final width = radius * 1.6;
    final height = radius * 0.6;
    final baseRect = Rect.fromCenter(
      center: position,
      width: width * 2,
      height: height * 2,
    );
    final rect = RRect.fromRectAndRadius(baseRect, const Radius.circular(18));
    final paint = Paint()
      ..shader = ui.Gradient.linear(baseRect.topLeft, baseRect.bottomRight, [
        color.withValues(alpha: 0.65),
        Colors.blueGrey.withValues(alpha: 0.4),
      ]);
    canvas.drawRRect(rect, paint);
    final portPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (var i = -3; i <= 3; i++) {
      final x = position.dx + i * (width / 7);
      canvas.drawLine(
        Offset(x, position.dy - height * 0.2),
        Offset(x, position.dy + height * 0.2),
        portPaint,
      );
    }
    if (isSelected) {
      canvas.drawRRect(
        rect.inflate(4),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white.withValues(alpha: 0.6),
      );
    }
  }

  void _drawGatewayPrism(
    Canvas canvas,
    Offset position,
    double radius,
    Color color,
    bool isSelected,
  ) {
    final path = Path()
      ..moveTo(position.dx, position.dy - radius)
      ..lineTo(position.dx + radius * 1.4, position.dy)
      ..lineTo(position.dx, position.dy + radius * 1.1)
      ..lineTo(position.dx - radius * 1.4, position.dy)
      ..close();
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(position.dx, position.dy - radius),
        Offset(position.dx, position.dy + radius),
        [Colors.white.withValues(alpha: 0.9), color.withValues(alpha: 0.6)],
      );
    canvas.drawPath(path, paint);
    if (isSelected) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white.withValues(alpha: 0.7),
      );
    }
  }

  void _drawSensorDisk(
    Canvas canvas,
    Offset position,
    double radius,
    Color color,
    bool isSelected,
  ) {
    final r = radius * 0.8;
    final paint = Paint()
      ..shader = ui.Gradient.radial(position, r * 1.3, [
        color.withValues(alpha: 0.9),
        Colors.blueGrey.withValues(alpha: 0.2),
      ]);
    canvas.drawOval(Rect.fromCircle(center: position, radius: r), paint);
    if (isSelected) {
      canvas.drawOval(
        Rect.fromCircle(center: position, radius: r + 4),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white.withValues(alpha: 0.6),
      );
    }
  }

  void _drawClientNode(
    Canvas canvas,
    Offset position,
    double radius,
    Color color,
    bool isSelected,
  ) {
    final path = Path()
      ..moveTo(position.dx, position.dy - radius)
      ..lineTo(position.dx + radius * 0.9, position.dy + radius * 0.6)
      ..lineTo(position.dx - radius * 0.9, position.dy + radius * 0.6)
      ..close();
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(position.dx, position.dy - radius),
        Offset(position.dx, position.dy + radius),
        [color.withValues(alpha: 0.8), Colors.blueGrey.withValues(alpha: 0.2)],
      );
    canvas.drawPath(path, paint);
    if (isSelected) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white.withValues(alpha: 0.7),
      );
    }
  }

  List<Offset> _isoDiamondPoints(Offset center, double radius) {
    final top = Offset(center.dx, center.dy - radius * 0.6);
    final right = Offset(center.dx + radius * 1.2, center.dy - radius * 0.05);
    final bottom = Offset(center.dx, center.dy + radius * 0.9);
    final left = Offset(center.dx - radius * 1.2, center.dy - radius * 0.05);
    return [top, right, bottom, left];
  }

  @override
  bool shouldRepaint(covariant _TwinScenePainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.mode != mode ||
      oldDelegate.selectedHost != selectedHost ||
      oldDelegate.heatMax != heatMax ||
      oldDelegate.cameraFrom != cameraFrom ||
      oldDelegate.cameraTo != cameraTo;
}

double twinScaleFactor(
  TwinStateFrame frame,
  Size size, {
  Map<String, TwinPosition>? layoutOverrides,
}) {
  final radius = _sceneRadius(frame, layoutOverrides);
  if (radius <= 0) return 1;
  const margin = 64.0;
  final shortest = size.shortestSide;
  if (!shortest.isFinite || shortest <= margin * 2) {
    return 1;
  }
  return ((shortest / 2) - margin) / radius;
}

double _sceneRadius(
  TwinStateFrame frame,
  Map<String, TwinPosition>? overrides,
) {
  if (frame.hosts.isEmpty) {
    return 1;
  }
  double maxRadius = 1;
  for (final host in frame.hosts) {
    final position = overrides != null && overrides[host.hostname] != null
        ? overrides[host.hostname]!
        : host.position;
    final distance = math.sqrt(
      position.x * position.x + position.z * position.z,
    );
    if (distance > maxRadius) {
      maxRadius = distance;
    }
  }
  return maxRadius;
}

Offset twinProjectPoint(
  TwinPosition position,
  Offset center,
  double scale, [
  TwinPosition focus = TwinPosition.zero,
]) {
  return _projectPoint3d(position, center, scale, focus).offset;
}

Offset _quadraticPoint(Offset p0, Offset p1, Offset p2, double t) {
  // 링크 베지어 곡선의 중간 포인트 계산.
  final omt = 1 - t;
  final x = omt * omt * p0.dx + 2 * omt * t * p1.dx + t * t * p2.dx;
  final y = omt * omt * p0.dy + 2 * omt * t * p1.dy + t * t * p2.dy;
  return Offset(x, y);
}

double hostBubbleRadius(TwinHost host) {
  // CPU 부하에 따라 노드 반경을 조정한다.
  if (host.isCore) {
    return 18.0;
  }
  final cpuLoad = host.metrics.cpuLoad.clamp(0.0, 100.0);
  return 8.0 + cpuLoad * 0.04;
}

Color _tierColor(int tier) {
  final index = (_tierLevel(tier) - 1).clamp(0, _kTierColors.length - 1);
  return _kTierColors[index];
}

/// 현재 노드 위치를 감싸는 좌표 범위 계산 결과.
class _SceneBounds {
  const _SceneBounds({
    required this.minX,
    required this.maxX,
    required this.minZ,
    required this.maxZ,
  });

  final double minX;
  final double maxX;
  final double minZ;
  final double maxZ;

  double get width => maxX - minX;
  double get depth => maxZ - minZ;
}

int _tierLevel(int? tier) {
  final normalized = tier ?? 3;
  return normalized.clamp(1, _kDefaultOsiLayers.length);
}

_SceneBounds _computeSceneBounds(
  Map<String, TwinPosition> overrides,
  TwinStateFrame frame,
) {
  double minX = double.infinity;
  double maxX = double.negativeInfinity;
  double minZ = double.infinity;
  double maxZ = double.negativeInfinity;
  for (final host in frame.hosts) {
    final position = overrides[host.hostname] ?? host.position;
    minX = math.min(minX, position.x);
    maxX = math.max(maxX, position.x);
    minZ = math.min(minZ, position.z);
    maxZ = math.max(maxZ, position.z);
  }
  if (!minX.isFinite) {
    minX = -400;
    maxX = 400;
    minZ = -400;
    maxZ = 400;
  }
  return _SceneBounds(minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ);
}

/// 디버그용 대시 경로를 그리는 유틸리티.
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

/// 3D 좌표를 투영한 결과(화면 오프셋 + 깊이/스케일).
class _ProjectedPoint {
  const _ProjectedPoint(this.offset, this.depth, this.scaleFactor);

  final Offset offset;
  final double depth;
  final double scaleFactor;
}

_ProjectedPoint _projectPoint3d(
  TwinPosition position,
  Offset center,
  double scale,
  TwinPosition focus,
) {
  final adjusted = position.subtract(focus);
  final cosYaw = math.cos(_cameraYaw);
  final sinYaw = math.sin(_cameraYaw);
  final xYaw = adjusted.x * cosYaw - adjusted.z * sinYaw;
  final zYaw = adjusted.x * sinYaw + adjusted.z * cosYaw;

  final cosPitch = math.cos(_cameraPitch);
  final sinPitch = math.sin(_cameraPitch);
  final yPitch = adjusted.y * cosPitch - zYaw * sinPitch;
  final depth = adjusted.y * sinPitch + zYaw * cosPitch;

  final perspective = _cameraDistance / (_cameraDistance + depth + 1);
  final screenX = center.dx + xYaw * scale * perspective;
  final screenY = center.dy + yPitch * scale * perspective;
  return _ProjectedPoint(Offset(screenX, screenY), depth, perspective);
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

String _formatCapacity(double? bytes) {
  if (bytes == null || bytes <= 0) return '정보 없음';
  const giga = 1024 * 1024 * 1024;
  final gb = bytes / giga;
  final decimals = gb >= 100 ? 0 : 1;
  return '${gb.toStringAsFixed(decimals)} GB';
}

String _summarizeDisks(List<TwinDiskUsage> disks) {
  if (disks.isEmpty) {
    return '데이터 없음';
  }
  double totalBytes = 0;
  for (final disk in disks) {
    if (disk.totalBytes != null) {
      totalBytes += disk.totalBytes!;
    }
  }
  if (disks.length == 1) {
    final disk = disks.first;
    return '${disk.mountpoint} · ${_formatCapacity(disk.totalBytes)}';
  }
  final capacity = totalBytes > 0 ? _formatCapacity(totalBytes) : '용량 미상';
  return '${disks.length} vols · $capacity';
}

String _formatInterfaceSummary(List<TwinInterfaceStats> interfaces) {
  if (interfaces.isEmpty) return '데이터 없음';
  TwinInterfaceStats? primary;
  for (final iface in interfaces) {
    if (iface.isUp != false) {
      primary = iface;
      break;
    }
  }
  primary ??= interfaces.first;
  return '${primary.name} · ${_formatInterfaceSpeed(primary)}';
}

String _formatThroughputLabel(double valueGbps) {
  if (valueGbps.isNaN || valueGbps <= 0) {
    return '0 bps';
  }
  final gigabits = valueGbps;
  if (gigabits >= 1) {
    final decimals = gigabits >= 10 ? 1 : 2;
    return '${gigabits.toStringAsFixed(decimals)} Gbps';
  }
  final megabits = gigabits * 1000;
  if (megabits >= 1) {
    final decimals = megabits >= 100 ? 0 : 1;
    return '${megabits.toStringAsFixed(decimals)} Mbps';
  }
  final kilobits = megabits * 1000;
  if (kilobits >= 1) {
    final decimals = kilobits >= 100 ? 0 : 1;
    return '${kilobits.toStringAsFixed(decimals)} Kbps';
  }
  final bits = kilobits * 1000;
  return bits >= 1
      ? '${bits.toStringAsFixed(bits >= 100 ? 0 : 1)} bps'
      : '0 bps';
}

int _resolveNetworkTier(TwinHost host) {
  final tags = host.diagnostics.tags;
  final candidates = [
    tags['net.layer'],
    tags['network.layer'],
    tags['tier'],
    tags['zone'],
    tags['osi'],
    tags['role'],
  ];
  for (final value in candidates) {
    if (value == null || value.isEmpty) continue;
    final parsed = int.tryParse(value);
    if (parsed != null) return _tierLevel(parsed);
    final keyword = value.toLowerCase();
    final mapped = _kTierKeywordMap[keyword];
    if (mapped != null) {
      return mapped;
    }
  }
  return _tierLevel((host.position.y / _tierHostElevation).round());
}

HostDeviceForm _resolveDeviceForm(TwinHost host) {
  final tags = host.diagnostics.tags.map(
    (k, v) => MapEntry(k.toLowerCase(), v.toLowerCase()),
  );
  String descriptor = '';
  descriptor =
      tags['device'] ??
      tags['type'] ??
      host.hardware.systemModel?.toLowerCase() ??
      host.platform.toLowerCase();
  if (descriptor.contains('switch') || descriptor.contains('router')) {
    return HostDeviceForm.switcher;
  }
  if (descriptor.contains('gateway') || descriptor.contains('wan')) {
    return HostDeviceForm.gateway;
  }
  if (descriptor.contains('pi') ||
      descriptor.contains('sensor') ||
      descriptor.contains('edge')) {
    return HostDeviceForm.sensor;
  }
  if (descriptor.contains('laptop') ||
      descriptor.contains('client') ||
      descriptor.contains('desktop')) {
    return HostDeviceForm.client;
  }
  return HostDeviceForm.server;
}

String _formLabel(HostDeviceForm form) {
  switch (form) {
    case HostDeviceForm.server:
      return '서버';
    case HostDeviceForm.switcher:
      return '스위치/공유기';
    case HostDeviceForm.gateway:
      return '게이트웨이/WAN';
    case HostDeviceForm.sensor:
      return '센서/엣지';
    case HostDeviceForm.client:
      return '클라이언트';
  }
}

String? _formatHostMemorySubtitle(TwinHost host) {
  final usedBytes = host.memoryUsedBytes;
  final totalBytes = host.memoryTotalBytes;
  if (usedBytes != null && totalBytes != null) {
    return '${_formatBytes(usedBytes)} / ${_formatBytes(totalBytes)}';
  }
  final percent = host.metrics.memoryUsedPercent;
  if (percent.isNaN) {
    return null;
  }
  return '사용 ${percent.clamp(0, 100).toStringAsFixed(1)}%';
}

/// 카드 배경으로 사용되는 글래스 스타일 래퍼.
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
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              primaryValue,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  caption!,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
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

/// 온도/센서 정보를 보여주는 카드.
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
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              primaryLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              secondaryLabel,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

class _ProcessPanel extends StatefulWidget {
  const _ProcessPanel({required this.host});

  final TwinHost host;

  @override
  State<_ProcessPanel> createState() => _ProcessPanelState();
}

class _ProcessPanelState extends State<_ProcessPanel> {
  static const _pageSize = 3;
  static const _rowHeight = 40.0;
  late final PageController _controller;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void didUpdateWidget(covariant _ProcessPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pageCount = _pages.length;
    if (_pageIndex >= pageCount && pageCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller.jumpToPage(0);
        setState(() => _pageIndex = 0);
      });
    }
  }

  List<List<TwinProcessSample>> get _pages {
    final processes = widget.host.diagnostics.topProcesses
        .take(12)
        .toList(growable: false);
    return _chunkList(processes, _pageSize);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    if (pages.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            '상위 프로세스',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text('데이터 없음', style: TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      );
    }

    const panelHeight = _pageSize * _rowHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '상위 프로세스',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: panelHeight,
          child: PageView.builder(
            controller: _controller,
            physics: const PageScrollPhysics(),
            itemCount: pages.length,
            onPageChanged: (value) => setState(() => _pageIndex = value),
            itemBuilder: (context, index) {
              final page = pages[index];
              return Column(
                children: page
                    .map((process) => _ProcessRow(process: process))
                    .toList(growable: false),
              );
            },
          ),
        ),
        if (pages.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _PageDots(count: pages.length, index: _pageIndex),
          ),
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

class _StoragePanel extends StatefulWidget {
  const _StoragePanel({required this.host});

  final TwinHost host;

  @override
  State<_StoragePanel> createState() => _StoragePanelState();
}

class _StoragePanelState extends State<_StoragePanel> {
  static const _pageSize = 2;
  static const _rowHeight = 54.0;
  late final PageController _controller;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  List<List<TwinDiskUsage>> get _pages {
    final disks = widget.host.diagnostics.disks.take(8).toList(growable: false);
    return _chunkList(disks, _pageSize);
  }

  @override
  void didUpdateWidget(covariant _StoragePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pageCount = _pages.length;
    if (_pageIndex >= pageCount && pageCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller.jumpToPage(0);
        setState(() => _pageIndex = 0);
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
    final pages = _pages;
    if (pages.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            '스토리지',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text('데이터 없음', style: TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      );
    }

    const panelHeight = _pageSize * _rowHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '스토리지',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: panelHeight,
          child: PageView.builder(
            controller: _controller,
            itemCount: pages.length,
            onPageChanged: (value) => setState(() => _pageIndex = value),
            itemBuilder: (context, index) {
              final page = pages[index];
              return Column(
                children: page
                    .map((disk) => _DiskUsageBar(disk: disk))
                    .toList(growable: false),
              );
            },
          ),
        ),
        if (pages.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _PageDots(count: pages.length, index: _pageIndex),
          ),
      ],
    );
  }
}

// === Widget dock system =====================================================

const int _kDockColumns = 4;
const int _kDockRows = 13;

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
    type: SidebarWidgetType.hostLink,
    wing: SidebarWing.right,
    column: 0,
    row: 0,
  ),
  _WidgetPlacementSeed(
    type: SidebarWidgetType.hostTemperature,
    wing: SidebarWing.right,
    column: 0,
    row: 2,
  ),
  _WidgetPlacementSeed(
    type: SidebarWidgetType.processes,
    wing: SidebarWing.right,
    column: 0,
    row: 4,
  ),
  _WidgetPlacementSeed(
    type: SidebarWidgetType.network,
    wing: SidebarWing.right,
    column: 0,
    row: 7,
  ),
  _WidgetPlacementSeed(
    type: SidebarWidgetType.storage,
    wing: SidebarWing.right,
    column: 0,
    row: 9,
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

/// 위젯 유형별 크기/제약/설명을 정의한 청사진.
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
    heightUnits: 3,
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
    heightUnits: 3,
    requiresHost: true,
    builder: _buildStorageWidget,
  ),
};

Widget _buildGlobalMetricsWidget(
  BuildContext context,
  _WidgetBuildContext data,
) {
  final frame = data.frame;
  final available = data.constraints.maxHeight;
  final gaugeSize = math.max(60.0, math.min(90.0, (available - 28) / 2));
  return _SidebarOverviewCard(
    frame: frame,
    gaugeSize: gaugeSize,
    focusHost: data.selectedHost,
  );
}

Widget _buildGlobalLinkWidget(BuildContext context, _WidgetBuildContext data) {
  final host = data.selectedHost;
  if (host != null) {
    final throughput = host.metrics.netThroughputGbps ?? 0;
    final capacity = host.metrics.netCapacityGbps;
    final utilization = capacity != null && capacity > 0
        ? (throughput / capacity).clamp(0.0, 1.0)
        : null;
    return _LinkStatusPanel(
      title: host.displayName,
      primaryValue: _formatThroughputLabel(throughput),
      caption: capacity != null
          ? '용량 ${_formatThroughputLabel(capacity)}'
          : '용량 정보 없음',
      utilization: utilization,
    );
  }

  final frame = data.frame;
  final throughput = frame.estimatedThroughput;
  final capacity = frame.totalLinkCapacity;
  final utilization = capacity > 0
      ? (throughput / capacity).clamp(0.0, 1.0)
      : null;
  return _LinkStatusPanel(
    title: '클러스터 링크',
    primaryValue: _formatThroughputLabel(throughput),
    caption: capacity > 0
        ? '용량 ${_formatThroughputLabel(capacity)}'
        : '용량 정보 없음',
    utilization: utilization,
  );
}

Widget _buildGlobalTemperatureWidget(
  BuildContext context,
  _WidgetBuildContext data,
) {
  final host = data.selectedHost;
  if (host != null) {
    return _hostTemperaturePanel(host);
  }
  final frame = data.frame;
  final maxTemp = frame.maxCpuTemperature > 0 ? frame.maxCpuTemperature : null;
  final avgTemp = frame.averageCpuTemperature > 0
      ? frame.averageCpuTemperature
      : null;
  return _TemperaturePanel(
    title: '클러스터 온도',
    primaryLabel: maxTemp != null ? '${maxTemp.toStringAsFixed(1)}℃' : 'N/A',
    secondaryLabel: avgTemp != null
        ? '평균 ${avgTemp.toStringAsFixed(1)}℃'
        : '센서 없음',
    progress: maxTemp != null ? (maxTemp / 110).clamp(0.0, 1.0) : null,
  );
}

Widget _buildCommandConsoleWidget(
  BuildContext context,
  _WidgetBuildContext data,
) => _CommandConsoleCard(frame: data.frame, selectedHost: data.selectedHost);

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
  return _LinkStatusPanel(
    title: host.displayName,
    primaryValue: throughput > 0
        ? _formatThroughputLabel(throughput)
        : '데이터 없음',
    caption: capacity != null
        ? '용량 ${_formatThroughputLabel(capacity)}'
        : '용량 정보 없음',
    utilization: utilization,
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
  return _hostTemperaturePanel(host);
}

_TemperaturePanel _hostTemperaturePanel(TwinHost host) {
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
      return 'CPU 센서 없음';
    }
    return '센서 없음';
  }();
  return _TemperaturePanel(
    title: host.displayName,
    primaryLabel: primary != null ? '${primary.toStringAsFixed(1)}℃' : '데이터 없음',
    secondaryLabel: secondary,
    progress: primary != null ? (primary / 110).clamp(0.0, 1.0) : null,
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

/// 초기 레이아웃 구성용 시드 데이터.
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

/// 실제 도킹된 위젯 인스턴스의 위치/크기 정보.
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

/// 사이드바 위젯 도킹 레이아웃을 관리하는 컨트롤러.
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

/// 도킹된 위젯을 4xN 격자에 렌더링하는 패널.
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
                padding: const EdgeInsets.fromLTRB(12, 30, 12, 12),
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

/// 간단한 페이지네이션 인디케이터 점.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 12 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive
                ? Colors.tealAccent
                : Colors.white.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

List<List<T>> _chunkList<T>(List<T> items, int size) {
  if (items.isEmpty || size <= 0) {
    return <List<T>>[];
  }
  final result = <List<T>>[];
  for (var i = 0; i < items.length; i += size) {
    result.add(items.sublist(i, math.min(i + size, items.length)));
  }
  return result;
}

/// 위젯을 드래그로 추가할 수 있는 팔레트 패널.
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

/// 팔레트 내 섹션 그룹.
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

/// 드래그 가능한 위젯 청사진 카드.
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
          Row(
            children: [
              Expanded(
                child: Text(
                  blueprint.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0x220C1A2A),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0x331B2333)),
                ),
                child: Text(
                  '${blueprint.widthUnits}×${blueprint.heightUnits}',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
            ],
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

/// 좌측 헤더에서 팔레트 토글 버튼.
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

class _TierButton extends StatelessWidget {
  const _TierButton({
    required this.focusedTier,
    required this.tiers,
    required this.onChanged,
  });

  final int? focusedTier;
  final List<int> tiers;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = focusedTier == null ? '전체 계층' : 'L$focusedTier';
    return PopupMenuButton<int?>(
      tooltip: '계층 선택',
      onSelected: onChanged,
      itemBuilder: (context) => [
        const PopupMenuItem<int?>(value: null, child: Text('모든 계층')),
        ...tiers.map(
          (tier) => PopupMenuItem<int?>(value: tier, child: Text('L$tier')),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x331B2333)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.filter_list, size: 16),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      ),
    );
  }
}

/// L1~L7 계층을 나타내는 사이드 도크. 드래그 타깃 겸 필터 버튼.
class _TierDock extends StatelessWidget {
  const _TierDock({
    required this.tiers,
    required this.focusedTier,
    required this.onFocusTier,
    required this.onDrop,
  });

  final List<int> tiers;
  final int? focusedTier;
  final ValueChanged<int?> onFocusTier;
  final void Function(String hostname, int tier) onDrop;

  @override
  Widget build(BuildContext context) {
    final ordered = tiers.toList()..sort();
    final display = ordered; // L1 at top
    return Material(
      color: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: display.map((tier) {
            return DragTarget<_TierDragPayload>(
              onWillAcceptWithDetails: (_) => true,
              onAcceptWithDetails: (details) {
                onDrop(details.data.hostname, tier);
                onFocusTier(tier);
              },
              builder: (context, candidateData, rejectedData) {
                final hovered = candidateData.isNotEmpty;
                final isActive = focusedTier == tier;
                final layerColor = _tierColor(tier);
                final bgColor = hovered
                    ? layerColor.withValues(alpha: 0.35)
                    : isActive
                    ? layerColor.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.08);
                return GestureDetector(
                  onTap: () => onFocusTier(isActive ? null : tier),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    width: 64,
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: hovered || isActive
                            ? layerColor
                            : Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'L$tier',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                );
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// 드래그 중인 호스트에 대한 메타데이터.
class _TierDragPayload {
  const _TierDragPayload({required this.hostname, required this.fromTier});

  final String hostname;
  final int fromTier;
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

class _DeviceIconMarker extends StatelessWidget {
  const _DeviceIconMarker({this.assetPath, required this.form});

  final String? assetPath;
  final HostDeviceForm form;

  @override
  Widget build(BuildContext context) {
    const double size = 32;
    Widget child;
    if (assetPath != null && assetPath!.isNotEmpty) {
      child = Image.asset(
        assetPath!,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildFallback(size),
      );
    } else {
      child = _buildFallback(size);
    }
    return child;
  }

  Widget _buildFallback(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0x3300C2FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x5500C2FF)),
      ),
      child: Icon(_iconForForm(form), size: size * 0.6, color: Colors.white),
    );
  }

  IconData _iconForForm(HostDeviceForm form) {
    switch (form) {
      case HostDeviceForm.server:
        return Icons.dns;
      case HostDeviceForm.switcher:
        return Icons.device_hub;
      case HostDeviceForm.gateway:
        return Icons.settings_ethernet;
      case HostDeviceForm.sensor:
        return Icons.sensors;
      case HostDeviceForm.client:
        return Icons.computer;
    }
  }
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
