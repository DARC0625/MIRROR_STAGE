import 'dart:async';
import 'dart:math' as math;

import 'package:logging/logging.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/twin_models.dart';

const _defaultTwinWsUrl =
    String.fromEnvironment('MIRROR_STAGE_WS_URL', defaultValue: 'http://localhost:3000/digital-twin');

/// 디지털 트윈 WebSocket 스트림을 구독하는 헬퍼 클래스.
class TwinChannel {
  TwinChannel({Uri? endpoint, bool connectImmediately = true})
      : _endpoint = endpoint ?? Uri.parse(_defaultTwinWsUrl),
        _connectImmediately = connectImmediately,
        _logger = Logger('EGO.TwinChannel');

  final Uri _endpoint;
  final bool _connectImmediately;
  final Logger _logger;
  final _controller = StreamController<TwinStateFrame>.broadcast();
  final _random = math.Random();

  io.Socket? _socket;
  bool _disposed = false;
  int _attempt = 0;

  /// TwinState 프레임을 브로드캐스트 스트림으로 제공.
  Stream<TwinStateFrame> stream() {
    if (!_controller.hasListener) {
      _controller.onListen = () {
        _controller.add(TwinStateFrame.empty());
        if (_connectImmediately) {
          _connect();
        }
      };
      _controller.onCancel = () async {
        await _disposeSocket();
        if (!_controller.isClosed) {
          await _controller.close();
        }
      };
    }
    return _controller.stream;
  }

  /// 소켓과 스트림을 정리한다.
  Future<void> dispose() async {
    await _disposeSocket();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  /// 소켓 리소스를 안전하게 정리한다.
  Future<void> _disposeSocket() async {
    _disposed = true;
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        socket.dispose();
      } catch (_) {
        socket.disconnect();
      }
    }
  }

  /// 백오프 전략으로 WebSocket 연결을 시도한다.
  void _connect() {
    if (_disposed || !_connectImmediately) {
      return;
    }

    final uri = _endpoint.toString();
    _logger.info('Connecting to digital twin channel at $uri (attempt $_attempt)');

    final socket = io.io(uri, {
      'transports': ['websocket'],
      'autoConnect': false,
      'reconnection': false,
      'forceNew': true,
    });

    _socket = socket;

    socket.onConnect((_) {
      _logger.info('Digital twin channel connected');
      _attempt = 0;
    });

    socket.onConnectError((error) {
      _logger.warning('Connect error: $error');
      socket.dispose();
      _scheduleReconnect();
    });

    socket.onError((error) {
      _logger.warning('Socket error: $error');
      _scheduleReconnect();
    });

    socket.onDisconnect((_) {
      _logger.info('Digital twin channel disconnected');
      _scheduleReconnect();
    });

    socket.on('twin-state', (dynamic payload) {
      try {
        final frame = TwinStateFrame.fromDynamic(payload);
        _controller.add(frame);
      } catch (error, stackTrace) {
        _logger.severe('Failed to decode twin state payload', error, stackTrace);
      }
    });

    socket.connect();
  }

  /// 지수 백오프 + 지터를 적용해 재연결한다.
  void _scheduleReconnect() {
    if (_disposed || !_connectImmediately) {
      return;
    }

    _attempt += 1;
    final capped = _attempt.clamp(0, 6);
    final backoff = Duration(milliseconds: 200 * (1 << capped));
    final jitter = Duration(milliseconds: _random.nextInt(250));
    final delay = backoff + jitter;

    _logger.info('Reconnecting to digital twin channel in ${delay.inMilliseconds}ms');
    Future.delayed(delay, () {
      if (_disposed) return;
      _connect();
    });
  }
}
