import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';

const double _bytesPerGiB = 1024 * 1024 * 1024;

String? _stringOrNull(dynamic value) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

double? _doubleOrNull(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  if (value is String) {
    final parsed = double.tryParse(value);
    return parsed?.isFinite == true ? parsed : null;
  }
  return null;
}

int? _intOrNull(dynamic value) {
  final parsed = _doubleOrNull(value);
  return parsed?.round();
}

enum TwinHostStatus { online, stale, offline }

const String _egoHostId = 'ego-hub';

class TwinPosition {
  const TwinPosition({required this.x, required this.y, required this.z});

  static const zero = TwinPosition(x: 0, y: 0, z: 0);

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

  TwinPosition subtract(TwinPosition other) =>
      TwinPosition(x: x - other.x, y: y - other.y, z: z - other.z);

  static TwinPosition lerp(TwinPosition a, TwinPosition b, double t) {
    return TwinPosition(
      x: a.x + (b.x - a.x) * t,
      y: a.y + (b.y - a.y) * t,
      z: a.z + (b.z - a.z) * t,
    );
  }
}

class HostMetricsSummary {
  const HostMetricsSummary({
    required this.cpuLoad,
    required this.memoryUsedPercent,
    required this.loadAverage,
    required this.uptimeSeconds,
    this.gpuTemperature,
    this.cpuTemperature,
    this.memoryTotalBytes,
    this.memoryAvailableBytes,
    this.netBytesTx,
    this.netBytesRx,
    this.netThroughputGbps,
    this.netCapacityGbps,
    this.swapUsedPercent,
    this.cpuPerCore = const [],
  });

  final double cpuLoad;
  final double memoryUsedPercent;
  final double loadAverage;
  final double uptimeSeconds;
  final double? gpuTemperature;
  final double? cpuTemperature;
  final double? memoryTotalBytes;
  final double? memoryAvailableBytes;
  final double? netBytesTx;
  final double? netBytesRx;
  final double? netThroughputGbps;
  final double? netCapacityGbps;
  final double? swapUsedPercent;
  final List<double> cpuPerCore;

  double? get memoryUsedBytes {
    if (memoryTotalBytes == null) {
      return null;
    }
    return memoryTotalBytes! * (memoryUsedPercent.clamp(0, 100) / 100);
  }

  factory HostMetricsSummary.fromJson(Map<String, dynamic> json) {
    return HostMetricsSummary(
      cpuLoad: (json['cpuLoad'] as num?)?.toDouble() ?? 0,
      memoryUsedPercent: (json['memoryUsedPercent'] as num?)?.toDouble() ?? 0,
      loadAverage: (json['loadAverage'] as num?)?.toDouble() ?? 0,
      uptimeSeconds: (json['uptimeSeconds'] as num?)?.toDouble() ?? 0,
      gpuTemperature: (json['gpuTemperature'] as num?)?.toDouble(),
      cpuTemperature: (json['cpuTemperature'] as num?)?.toDouble(),
      memoryTotalBytes:
          (json['memoryTotalBytes'] as num?)?.toDouble() ??
          (json['memory_total_bytes'] as num?)?.toDouble(),
      memoryAvailableBytes:
          (json['memoryAvailableBytes'] as num?)?.toDouble() ??
          (json['memory_available_bytes'] as num?)?.toDouble(),
      netBytesTx: (json['netBytesTx'] as num?)?.toDouble(),
      netBytesRx: (json['netBytesRx'] as num?)?.toDouble(),
      netThroughputGbps: (json['netThroughputGbps'] as num?)?.toDouble(),
      netCapacityGbps: (json['netCapacityGbps'] as num?)?.toDouble(),
      swapUsedPercent: (json['swapUsedPercent'] as num?)?.toDouble(),
      cpuPerCore: ((json['cpuPerCore'] as List<dynamic>?) ?? const [])
          .map((value) => (value as num?)?.toDouble())
          .whereType<double>()
          .toList(growable: false),
    );
  }
}

class HostHardwareSummary {
  const HostHardwareSummary({
    this.systemManufacturer,
    this.systemModel,
    this.biosVersion,
    this.cpuModel,
    this.cpuPhysicalCores,
    this.cpuLogicalCores,
    this.memoryTotalBytes,
    this.osDistro,
    this.osRelease,
    this.osKernel,
  });

  final String? systemManufacturer;
  final String? systemModel;
  final String? biosVersion;
  final String? cpuModel;
  final int? cpuPhysicalCores;
  final int? cpuLogicalCores;
  final double? memoryTotalBytes;
  final String? osDistro;
  final String? osRelease;
  final String? osKernel;

  factory HostHardwareSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const HostHardwareSummary();
    }
    return HostHardwareSummary(
      systemManufacturer:
          _stringOrNull(json['systemManufacturer']) ??
          _stringOrNull(json['system_manufacturer']),
      systemModel:
          _stringOrNull(json['systemModel']) ??
          _stringOrNull(json['system_model']),
      biosVersion:
          _stringOrNull(json['biosVersion']) ??
          _stringOrNull(json['bios_version']),
      cpuModel:
          _stringOrNull(json['cpuModel']) ?? _stringOrNull(json['cpu_model']),
      cpuPhysicalCores: _intOrNull(
        json['cpuPhysicalCores'] ?? json['cpu_physical_cores'],
      ),
      cpuLogicalCores: _intOrNull(
        json['cpuLogicalCores'] ?? json['cpu_logical_cores'],
      ),
      memoryTotalBytes: _doubleOrNull(
        json['memoryTotalBytes'] ?? json['memory_total_bytes'],
      ),
      osDistro: _stringOrNull(json['osDistro'] ?? json['os_distro']),
      osRelease: _stringOrNull(json['osRelease'] ?? json['os_release']),
      osKernel: _stringOrNull(json['osKernel'] ?? json['os_kernel']),
    );
  }

  HostHardwareSummary merge(HostHardwareSummary fallback) {
    if (identical(this, fallback)) return this;
    return HostHardwareSummary(
      systemManufacturer: systemManufacturer ?? fallback.systemManufacturer,
      systemModel: systemModel ?? fallback.systemModel,
      biosVersion: biosVersion ?? fallback.biosVersion,
      cpuModel: cpuModel ?? fallback.cpuModel,
      cpuPhysicalCores: cpuPhysicalCores ?? fallback.cpuPhysicalCores,
      cpuLogicalCores: cpuLogicalCores ?? fallback.cpuLogicalCores,
      memoryTotalBytes: memoryTotalBytes ?? fallback.memoryTotalBytes,
      osDistro: osDistro ?? fallback.osDistro,
      osRelease: osRelease ?? fallback.osRelease,
      osKernel: osKernel ?? fallback.osKernel,
    );
  }
}

class TwinProcessSample {
  const TwinProcessSample({
    required this.pid,
    required this.name,
    required this.cpuPercent,
    this.memoryPercent,
    this.username,
  });

  final int pid;
  final String name;
  final double cpuPercent;
  final double? memoryPercent;
  final String? username;

  factory TwinProcessSample.fromJson(Map<String, dynamic> json) =>
      TwinProcessSample(
        pid: json['pid'] as int? ?? 0,
        name: json['name'] as String? ?? 'process',
        cpuPercent:
            (json['cpuPercent'] as num?)?.toDouble() ??
            (json['cpu_percent'] as num?)?.toDouble() ??
            0,
        memoryPercent:
            (json['memoryPercent'] as num?)?.toDouble() ??
            (json['memory_percent'] as num?)?.toDouble(),
        username: json['username'] as String? ?? json['user'] as String?,
      );
}

class TwinDiskUsage {
  const TwinDiskUsage({
    required this.device,
    required this.mountpoint,
    this.totalBytes,
    this.usedBytes,
    this.usedPercent,
  });

  final String device;
  final String mountpoint;
  final double? totalBytes;
  final double? usedBytes;
  final double? usedPercent;

  factory TwinDiskUsage.fromJson(Map<String, dynamic> json) => TwinDiskUsage(
    device: json['device'] as String? ?? 'disk',
    mountpoint:
        json['mountpoint'] as String? ?? json['path'] as String? ?? 'disk',
    totalBytes:
        (json['totalBytes'] as num?)?.toDouble() ??
        (json['total_bytes'] as num?)?.toDouble(),
    usedBytes:
        (json['usedBytes'] as num?)?.toDouble() ??
        (json['used_bytes'] as num?)?.toDouble(),
    usedPercent:
        (json['usedPercent'] as num?)?.toDouble() ??
        (json['used_percent'] as num?)?.toDouble(),
  );
}

class TwinInterfaceStats {
  const TwinInterfaceStats({
    required this.name,
    this.speedMbps,
    this.isUp,
    this.bytesSent,
    this.bytesRecv,
  });

  final String name;
  final double? speedMbps;
  final bool? isUp;
  final double? bytesSent;
  final double? bytesRecv;

  String get speedLabel {
    if (speedMbps == null) {
      return '$name · N/A';
    }
    if (speedMbps! >= 1000) {
      return '$name · ${(speedMbps! / 1000).toStringAsFixed(1)} Gbps';
    }
    return '$name · ${speedMbps!.toStringAsFixed(0)} Mbps';
  }

  factory TwinInterfaceStats.fromJson(Map<String, dynamic> json) =>
      TwinInterfaceStats(
        name: json['name'] as String? ?? 'iface',
        speedMbps:
            (json['speedMbps'] as num?)?.toDouble() ??
            (json['speed_mbps'] as num?)?.toDouble(),
        isUp: json['isUp'] as bool? ?? json['is_up'] as bool?,
        bytesSent:
            (json['bytesSent'] as num?)?.toDouble() ??
            (json['bytes_sent'] as num?)?.toDouble(),
        bytesRecv:
            (json['bytesRecv'] as num?)?.toDouble() ??
            (json['bytes_recv'] as num?)?.toDouble(),
      );
}

class TwinDiagnostics {
  const TwinDiagnostics({
    this.cpuPerCore = const [],
    this.swapUsedPercent,
    this.topProcesses = const [],
    this.disks = const [],
    this.interfaces = const [],
    this.tags = const {},
  });

  final List<double> cpuPerCore;
  final double? swapUsedPercent;
  final List<TwinProcessSample> topProcesses;
  final List<TwinDiskUsage> disks;
  final List<TwinInterfaceStats> interfaces;
  final Map<String, String> tags;

  bool get isSeed => tags.containsKey('profile') && tags['profile'] == 'seed';

  factory TwinDiagnostics.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const TwinDiagnostics();
    }
    return TwinDiagnostics(
      cpuPerCore: ((json['cpuPerCore'] as List<dynamic>?) ?? const [])
          .map((value) => (value as num?)?.toDouble())
          .whereType<double>()
          .toList(growable: false),
      swapUsedPercent: (json['swapUsedPercent'] as num?)?.toDouble(),
      topProcesses: ((json['topProcesses'] as List<dynamic>?) ?? const [])
          .map(
            (entry) =>
                TwinProcessSample.fromJson(entry as Map<String, dynamic>),
          )
          .toList(growable: false),
      disks: ((json['disks'] as List<dynamic>?) ?? const [])
          .map((entry) => TwinDiskUsage.fromJson(entry as Map<String, dynamic>))
          .toList(growable: false),
      interfaces: ((json['interfaces'] as List<dynamic>?) ?? const [])
          .map(
            (entry) =>
                TwinInterfaceStats.fromJson(entry as Map<String, dynamic>),
          )
          .toList(growable: false),
      tags: Map<String, String>.from(
        json['tags'] as Map? ?? const <String, String>{},
      ),
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
    required this.hardware,
    this.label,
    this.rack,
    this.diagnostics = const TwinDiagnostics(),
    this.isSynthetic = false,
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
  final HostHardwareSummary hardware;
  final String? rack;
  final TwinDiagnostics diagnostics;
  final bool isSynthetic;

  bool get isEgo => hostname == _egoHostId;
  bool get isCore => isEgo;

  double get uptimeHours => metrics.uptimeSeconds / 3600.0;
  Duration get uptime => Duration(seconds: metrics.uptimeSeconds.ceil());

  String get displayLabel => label ?? '$displayName\n$ip';

  double? get cpuTemperature => metrics.cpuTemperature;
  double? get gpuTemperature => metrics.gpuTemperature;

  double? get memoryTotalBytes =>
      metrics.memoryTotalBytes ?? hardware.memoryTotalBytes;

  double? get memoryAvailableBytes {
    if (metrics.memoryAvailableBytes != null) {
      return metrics.memoryAvailableBytes;
    }
    final total = memoryTotalBytes;
    final used = memoryUsedBytes;
    if (total != null && used != null) {
      return (total - used).clamp(0, total);
    }
    return null;
  }

  double? get memoryUsedBytes {
    if (metrics.memoryUsedBytes != null) {
      return metrics.memoryUsedBytes;
    }
    final total = memoryTotalBytes;
    if (total == null) return null;
    return total * (metrics.memoryUsedPercent.clamp(0, 100) / 100);
  }

  String get osDisplay {
    final distro = hardware.osDistro ?? platform;
    final release = hardware.osRelease;
    if (release != null && release.isNotEmpty) {
      return '${distro.trim()} $release'.trim();
    }
    return distro.trim();
  }

  String get cpuSummary {
    final model = hardware.cpuModel;
    final physical = hardware.cpuPhysicalCores;
    final logical = hardware.cpuLogicalCores;
    if (model == null && physical == null && logical == null) {
      return 'N/A';
    }
    final parts = <String>[];
    if (model != null) {
      parts.add(model);
    }
    if (physical != null) {
      parts.add('P$physical');
    }
    if (logical != null) {
      parts.add('L$logical');
    }
    return parts.join(' · ');
  }

  factory TwinHost.fromJson(Map<String, dynamic> json) {
    final statusString = (json['status'] as String? ?? 'offline').toLowerCase();
    final rawHardware = HostHardwareSummary.fromJson(
      json['hardware'] as Map<String, dynamic>?,
    );
    final derivedHardware = HostHardwareSummary.fromJson(json);
    final hardware = rawHardware.merge(derivedHardware);
    return TwinHost(
      hostname: json['hostname'] as String? ?? 'unknown',
      displayName: json['displayName'] as String? ?? 'Unknown Host',
      ip: json['ip'] as String? ?? '0.0.0.0',
      label: json['label'] as String?,
      status: TwinHostStatus.values.firstWhere(
        (value) => value.name == statusString,
        orElse: () => TwinHostStatus.offline,
      ),
      lastSeen:
          DateTime.tryParse(json['lastSeen'] as String? ?? '') ??
          DateTime.now().toUtc(),
      agentVersion: json['agentVersion'] as String? ?? 'unknown',
      platform: json['platform'] as String? ?? 'unknown',
      metrics: HostMetricsSummary.fromJson(
        (json['metrics'] as Map<String, dynamic>? ?? const {}),
      ),
      position: TwinPosition.fromJson(
        (json['position'] as Map<String, dynamic>? ?? const {}),
      ),
      hardware: hardware,
      rack: json['rack'] as String?,
      diagnostics: TwinDiagnostics.fromJson(
        json['diagnostics'] as Map<String, dynamic>?,
      ),
      isSynthetic: json['isSynthetic'] as bool? ?? false,
    );
  }

  bool get isDummy => isSynthetic || diagnostics.isSeed;
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
      hosts
          .where(
            (host) => !host.isCore && host.status != TwinHostStatus.offline,
          )
          .toList()
        ..sort((a, b) => b.metrics.cpuLoad.compareTo(a.metrics.cpuLoad));

  double get averageCpuLoad {
    final relevant = hosts.where((host) => !host.isCore);
    if (relevant.isEmpty) return 0;
    final sum = relevant.fold<double>(
      0,
      (acc, host) => acc + host.metrics.cpuLoad,
    );
    return sum / relevant.length;
  }

  double get averageMemoryLoad {
    final relevant = hosts.where((host) => !host.isCore);
    if (relevant.isEmpty) return 0;
    final sum = relevant.fold<double>(
      0,
      (acc, host) => acc + host.metrics.memoryUsedPercent,
    );
    return sum / relevant.length;
  }

  int get onlineHosts => hosts
      .where((host) => !host.isCore && host.status == TwinHostStatus.online)
      .length;

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
      generatedAt:
          DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
      hosts: hosts,
      links: links,
    );
  }

  factory TwinStateFrame.fromDynamic(dynamic payload) {
    if (payload is String) {
      return TwinStateFrame.fromJson(
        jsonDecode(payload) as Map<String, dynamic>,
      );
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

  double get maxCpuTemperature {
    double maxValue = 0;
    for (final host in hosts) {
      if (host.isCore) continue;
      final temp = host.cpuTemperature ?? host.gpuTemperature;
      if (temp != null && temp > maxValue) {
        maxValue = temp;
      }
    }
    return maxValue;
  }

  double get averageCpuTemperature {
    double sum = 0;
    int count = 0;
    for (final host in hosts) {
      if (host.isCore) continue;
      final temp = host.cpuTemperature ?? host.gpuTemperature;
      if (temp != null) {
        sum += temp;
        count += 1;
      }
    }
    if (count == 0) return 0;
    return sum / count;
  }

  double get totalMemoryCapacityGb {
    double total = 0;
    for (final host in hosts) {
      if (host.isCore) continue;
      final capacity = host.memoryTotalBytes;
      if (capacity != null) {
        total += capacity / _bytesPerGiB;
      }
    }
    return total;
  }

  double get totalMemoryUsedGb {
    double total = 0;
    for (final host in hosts) {
      if (host.isCore) continue;
      final used = host.memoryUsedBytes;
      if (used != null) {
        total += used / _bytesPerGiB;
      }
    }
    return total;
  }

  double get memoryUtilizationPercent {
    final capacityGb = totalMemoryCapacityGb;
    if (capacityGb <= 0) return 0;
    final usedGb = totalMemoryUsedGb;
    return (usedGb / capacityGb) * 100;
  }

  double get maxRadius {
    if (hosts.isEmpty) return 1;
    return hosts
        .where((host) => !host.isCore)
        .map(
          (host) => math.sqrt(
            host.position.x * host.position.x +
                host.position.z * host.position.z,
          ),
        )
        .fold<double>(1, math.max);
  }
}
