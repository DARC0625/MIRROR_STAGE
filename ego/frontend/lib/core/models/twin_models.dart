import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';

enum TwinHostStatus { online, stale, offline }

const String _egoHostId = 'ego-hub';

class TwinPosition {
  const TwinPosition({required this.x, required this.y, required this.z});

  final double x;
  final double y;
  final double z;

  factory TwinPosition.fromJson(Map<String, dynamic> json) {
    return TwinPosition(
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      z: (json['z'] as num?)?.toDouble() ?? 0,
    );
  }

  TwinPosition scale(double factor) =>
      TwinPosition(x: x * factor, y: y * factor, z: z * factor);
}

class HostMetricsSummary {
  const HostMetricsSummary({
    required this.cpuLoad,
    required this.memoryUsedPercent,
    required this.loadAverage,
    required this.uptimeSeconds,
    this.gpuTemperature,
    this.netBytesTx,
    this.netBytesRx,
    this.netThroughputGbps,
    this.netCapacityGbps,
  });

  final double cpuLoad;
  final double memoryUsedPercent;
  final double loadAverage;
  final double uptimeSeconds;
  final double? gpuTemperature;
  final double? netBytesTx;
  final double? netBytesRx;
  final double? netThroughputGbps;
  final double? netCapacityGbps;

  factory HostMetricsSummary.fromJson(Map<String, dynamic> json) {
    return HostMetricsSummary(
      cpuLoad: (json['cpuLoad'] as num?)?.toDouble() ?? 0,
      memoryUsedPercent: (json['memoryUsedPercent'] as num?)?.toDouble() ?? 0,
      loadAverage: (json['loadAverage'] as num?)?.toDouble() ?? 0,
      uptimeSeconds: (json['uptimeSeconds'] as num?)?.toDouble() ?? 0,
      gpuTemperature: (json['gpuTemperature'] as num?)?.toDouble(),
      netBytesTx: (json['netBytesTx'] as num?)?.toDouble(),
      netBytesRx: (json['netBytesRx'] as num?)?.toDouble(),
      netThroughputGbps: (json['netThroughputGbps'] as num?)?.toDouble(),
      netCapacityGbps: (json['netCapacityGbps'] as num?)?.toDouble(),
    );
  }
}

class TwinHost {
  const TwinHost({
    required this.hostname,
    required this.displayName,
    required this.ip,
    required this.status,
    required this.lastSeen,
    required this.agentVersion,
    required this.platform,
    required this.metrics,
    required this.position,
    this.label,
    this.rack,
  });

  final String hostname;
  final String displayName;
  final String ip;
  final String? label;
  final TwinHostStatus status;
  final DateTime lastSeen;
  final String agentVersion;
  final String platform;
  final HostMetricsSummary metrics;
  final TwinPosition position;
  final String? rack;

  bool get isEgo => hostname == _egoHostId;
  bool get isCore => isEgo;

  double get uptimeHours => metrics.uptimeSeconds / 3600.0;

  String get displayLabel => label ?? '${displayName}\n$ip';

  factory TwinHost.fromJson(Map<String, dynamic> json) {
    final statusString = (json['status'] as String? ?? 'offline').toLowerCase();
    return TwinHost(
      hostname: json['hostname'] as String? ?? 'unknown',
      displayName: json['displayName'] as String? ?? 'Unknown Host',
      ip: json['ip'] as String? ?? '0.0.0.0',
      label: json['label'] as String?,
      status: TwinHostStatus.values.firstWhere(
        (value) => value.name == statusString,
        orElse: () => TwinHostStatus.offline,
      ),
      lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? '') ?? DateTime.now().toUtc(),
      agentVersion: json['agentVersion'] as String? ?? 'unknown',
      platform: json['platform'] as String? ?? 'unknown',
      metrics: HostMetricsSummary.fromJson(
        (json['metrics'] as Map<String, dynamic>? ?? const {}),
      ),
      position: TwinPosition.fromJson(
        (json['position'] as Map<String, dynamic>? ?? const {}),
      ),
      rack: json['rack'] as String?,
    );
  }
}

class TwinLink {
  const TwinLink({
    required this.id,
    required this.source,
    required this.target,
    required this.throughputGbps,
    required this.utilization,
    this.capacityGbps,
  });

  final String id;
  final String source;
  final String target;
  final double throughputGbps;
  final double utilization;
  final double? capacityGbps;

  factory TwinLink.fromJson(Map<String, dynamic> json) {
    return TwinLink(
      id: json['id'] as String? ?? '',
      source: json['source'] as String? ?? '',
      target: json['target'] as String? ?? '',
      throughputGbps: (json['throughputGbps'] as num?)?.toDouble() ?? 0,
      utilization: (json['utilization'] as num?)?.toDouble() ?? 0,
      capacityGbps: (json['capacityGbps'] as num?)?.toDouble(),
    );
  }
}

class TwinStateFrame {
  const TwinStateFrame({
    required this.twinId,
    required this.generatedAt,
    required this.hosts,
    required this.links,
  });

  final String twinId;
  final DateTime generatedAt;
  final List<TwinHost> hosts;
  final List<TwinLink> links;

  UnmodifiableListView<TwinHost> get allHosts => UnmodifiableListView(hosts);

  List<TwinHost> get activeHosts =>
      hosts.where((host) => !host.isCore && host.status != TwinHostStatus.offline).toList()
        ..sort((a, b) => b.metrics.cpuLoad.compareTo(a.metrics.cpuLoad));

  double get averageCpuLoad {
    final relevant = hosts.where((host) => !host.isCore);
    if (relevant.isEmpty) return 0;
    final sum = relevant.fold<double>(0, (acc, host) => acc + host.metrics.cpuLoad);
    return sum / relevant.length;
  }

  double get averageMemoryLoad {
    final relevant = hosts.where((host) => !host.isCore);
    if (relevant.isEmpty) return 0;
    final sum = relevant.fold<double>(0, (acc, host) => acc + host.metrics.memoryUsedPercent);
    return sum / relevant.length;
  }

  int get onlineHosts =>
      hosts.where((host) => !host.isCore && host.status == TwinHostStatus.online).length;

  int get totalHosts => hosts.where((host) => !host.isCore).length;

  TwinHost? hostByName(String name) =>
      hosts.firstWhereOrNull((host) => host.hostname == name);

  factory TwinStateFrame.empty() => TwinStateFrame(
        twinId: 'project5',
        generatedAt: DateTime.now().toUtc(),
        hosts: const [],
        links: const [],
      );

  factory TwinStateFrame.fromJson(Map<String, dynamic> json) {
    final hosts = (json['hosts'] as List<dynamic>? ?? const [])
        .map((item) => TwinHost.fromJson(item as Map<String, dynamic>))
        .toList();
    final links = (json['links'] as List<dynamic>? ?? const [])
        .map((item) => TwinLink.fromJson(item as Map<String, dynamic>))
        .toList();
    return TwinStateFrame(
      twinId: json['twinId'] as String? ?? 'project5',
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
      hosts: hosts,
      links: links,
    );
  }

  factory TwinStateFrame.fromDynamic(dynamic payload) {
    if (payload is String) {
      return TwinStateFrame.fromJson(jsonDecode(payload) as Map<String, dynamic>);
    }
    if (payload is Map<String, dynamic>) {
      return TwinStateFrame.fromJson(payload);
    }
    throw ArgumentError('Unsupported twin payload: ${payload.runtimeType}');
  }

  TwinStateFrame mergeFallback(TwinStateFrame previous) {
    if (hosts.isNotEmpty) {
      return this;
    }
    return previous;
  }

  double get linkUtilization {
    if (links.isEmpty) return 0;
    final sum = links.fold<double>(0, (acc, link) => acc + link.utilization);
    return sum / links.length;
  }

  double get estimatedThroughput {
    if (links.isEmpty) return 0;
    return links.fold<double>(0, (acc, link) => acc + link.throughputGbps);
  }

  double get totalLinkCapacity {
    if (links.isEmpty) return 0;
    return links.fold<double>(0, (acc, link) => acc + (link.capacityGbps ?? 0));
  }

  double get maxHostThroughput {
    return hosts
        .where((host) => !host.isCore)
        .map((host) => host.metrics.netThroughputGbps ?? 0)
        .fold<double>(0, math.max);
  }

  double get maxRadius {
    if (hosts.isEmpty) return 1;
    return hosts
        .where((host) => !host.isCore)
        .map((host) => math.sqrt(
              host.position.x * host.position.x +
                  host.position.z * host.position.z,
            ))
        .fold<double>(1, math.max);
  }
}
