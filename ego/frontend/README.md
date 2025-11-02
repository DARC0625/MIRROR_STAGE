# MIRROR STAGE – EGO Frontend (Flutter)

이 앱은 10.0.0.0/24 내부망의 자산을 실시간 디지털 트윈으로 시각화하는 MIRROR STAGE의 지휘본부(EGO) 뷰어입니다. 벽걸이형 디지털 액자처럼 상시 구동할 수 있도록 Web/데스크톱/모바일을 동일한 코드베이스로 지원합니다.

## 개발 환경

### 1. Flutter SDK
- FVM으로 Flutter 3.35.5를 고정합니다.
  ```bash
  cd ego/frontend
  fvm install 3.35.5   # 최초 1회
  fvm use 3.35.5
  fvm flutter pub get
  ```
- FVM을 사용하지 않을 경우 현재 시스템 Flutter 3.35.5 이상을 권장합니다.

### 2. 실행
```bash
cd ego/frontend
fvm flutter run -d chrome        # Web
fvm flutter run -d linux-desktop # Linux 데스크톱
fvm flutter run -d windows       # Windows
fvm flutter run -d macos         # macOS
```

## 주요 모듈
- `lib/main.dart` : 앱 테마, 디지털 트윈 셸, CustomPainter 기반 2.5D 뷰포트
- `lib/core/models/twin_models.dart` : Socket.IO 응답을 도메인 오브젝트로 역직렬화하는 모델 계층
- `lib/core/services/twin_channel.dart` : 자동 재접속, 지터가 적용된 WebSocket(Soket.IO) 채널 래퍼

뷰포트는 현재 CustomPainter로 호스트/링크를 2.5D로 표현하며, 이후 three_dart/WebGL 브리지를 통해 진짜 3D 디지털 트윈을 적용할 예정입니다.

## 런타임 설정
- `MIRROR_STAGE_WS_URL` (dart-define): 기본값 `http://localhost:3000/digital-twin`
  ```bash
  fvm flutter run -d chrome --dart-define=MIRROR_STAGE_WS_URL=http://10.0.0.100:3000/digital-twin
  ```
- 테스트 실행 시 네트워크 연결을 끄고 싶다면 `TwinChannel(connectImmediately: false)`를 주입하세요. 기본 위젯 테스트는 이미 이 옵션을 사용합니다.

## 테스트
```bash
cd ego/frontend
flutter test
```

## 향후 작업
- three.js(또는 Impeller) 기반의 완전한 3D 씬 렌더러 연결
- Riverpod/Zustand 계층으로 상태 분리 및 지속화
- 모바일 레이아웃 최적화와 제스처(줌/회전) 지원
