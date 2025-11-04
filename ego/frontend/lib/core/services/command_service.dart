import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/command_models.dart';

const String _defaultApiBase = String.fromEnvironment(
  'MIRROR_STAGE_API_BASE',
  defaultValue: 'http://localhost:3000/api',
);

class CommandService {
  CommandService({http.Client? client, String? apiBase})
    : _client = client ?? http.Client(),
      _apiBase = apiBase ?? _defaultApiBase;

  final http.Client _client;
  final String _apiBase;

  Uri _baseUri() => Uri.parse('$_apiBase/commands');

  Future<CommandPage> listCommands({
    String? hostname,
    CommandStatus? status,
    String? search,
    int page = 1,
    int pageSize = 20,
  }) async {
    final params = <String, String>{'page': '$page', 'pageSize': '$pageSize'};
    if (hostname != null && hostname.isNotEmpty) {
      params['hostname'] = hostname;
    }
    if (status != null) {
      params['status'] = status.name;
    }
    if (search != null && search.trim().isNotEmpty) {
      params['search'] = search.trim();
    }

    final uri = _baseUri().replace(queryParameters: params);
    final response = await _client.get(uri);
    if (response.statusCode >= 400) {
      throw Exception('명령 목록을 가져오지 못했습니다 (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return CommandPage.fromJson(payload);
  }

  Future<CommandJob> createCommand({
    required String hostname,
    required String command,
    double? timeoutSeconds,
  }) async {
    final body = <String, dynamic>{
      'hostname': hostname,
      'command': command,
      if (timeoutSeconds != null) 'timeoutSeconds': timeoutSeconds,
    };
    final response = await _client.post(
      _baseUri(),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode >= 400) {
      throw Exception('명령 생성 실패 (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return CommandJob.fromJson(payload);
  }

  void dispose() {
    _client.close();
  }
}
