import 'package:intl/intl.dart';

enum CommandStatus { pending, running, succeeded, failed, timeout }

/// 명령 한 건의 DTO.
class CommandJob {
  const CommandJob({
    required this.id,
    required this.hostname,
    required this.command,
    required this.status,
    required this.requestedAt,
    this.startedAt,
    this.completedAt,
    this.exitCode,
    this.stdout,
    this.stderr,
    this.timeoutSeconds,
  });

  final String id;
  final String hostname;
  final String command;
  final CommandStatus status;
  final DateTime requestedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int? exitCode;
  final String? stdout;
  final String? stderr;
  final double? timeoutSeconds;

  factory CommandJob.fromJson(Map<String, dynamic> json) {
    final statusString = (json['status'] as String? ?? 'pending').toLowerCase();
    return CommandJob(
      id: json['id'] as String? ?? '',
      hostname: json['hostname'] as String? ?? 'unknown',
      command: json['command'] as String? ?? '',
      status: CommandStatus.values.firstWhere(
        (value) => value.name == statusString,
        orElse: () => CommandStatus.pending,
      ),
      requestedAt:
          DateTime.tryParse(json['requestedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
      completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
      exitCode: json['exitCode'] as int?,
      stdout: json['stdout'] as String?,
      stderr: json['stderr'] as String?,
      timeoutSeconds: (json['timeoutSeconds'] as num?)?.toDouble(),
    );
  }

  String get statusLabel {
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

  String get requestedLabel => DateFormat.Hms().format(requestedAt.toLocal());

  Duration? get duration {
    if (startedAt == null || completedAt == null) {
      return null;
    }
    return completedAt!.difference(startedAt!);
  }
}

/// 명령 목록 + 페이지네이션 정보를 담는 DTO.
class CommandPage {
  const CommandPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<CommandJob> items;
  final int total;
  final int page;
  final int pageSize;

  bool get hasMore => page * pageSize < total;

  factory CommandPage.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'] as List<dynamic>? ?? const [];
    return CommandPage(
      items: itemsRaw
          .map((entry) => CommandJob.fromJson(entry as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? itemsRaw.length,
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageSize: (json['pageSize'] as num?)?.toInt() ?? itemsRaw.length,
    );
  }
}
