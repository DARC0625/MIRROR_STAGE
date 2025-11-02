# MIRROR STAGE – EGO Backend (NestJS)

NestJS 기반 수집/명령 게이트웨이 서비스입니다. 내부망(10.0.0.0/24) 호스트의 실시간 메트릭을 수집하고, MIRROR STAGE 디지털 트윈으로 상태를 브로드캐스트합니다. 10.0.0.100 EGO 서버에서 실행합니다.

## 로컬 개발 환경

### 1. Node.js
- 이 디렉터리에는 전용 Node 20.18.0 바이너리가 포함되어 있습니다: `./.node`.
- 환경 진입 예시:
  ```bash
  cd ego/backend
  export PATH="$(pwd)/.node/bin:$PATH"
  npm install
  ```
- 전역 npm 대신 로컬 `.node` 환경에서만 패키지를 설치/업데이트하세요.

### 2. 의존성 설치
```bash
export PATH="$(pwd)/.node/bin:$PATH"
npm install
```

### 3. 실행
```bash
npm run start        # 개발 모드
npm run start:dev    # 파일 감시 모드
npm run start:prod   # 프로덕션 빌드 실행
```

### 4. 테스트
```bash
npm test             # 단위 테스트
npm run test:e2e     # E2E 테스트
npm run test:cov     # 커버리지
```

## REST API
- `GET /api/health` : 상태 체크(200 ➝ `ok`).
- `POST /api/metrics/batch` : 에이전트가 배치 전송한 메트릭 수집. `accepted` 카운터와 수신 시간을 반환하며 Zod 스키마로 유효성 검사합니다.
- `GET /api/twin/state` : 현재 디지털 트윈 스냅샷(JSON)

## 실시간 채널
- Socket.IO 네임스페이스: `ws://<host>:3000/digital-twin`
- 이벤트: `twin-state`
  ```json
  {
    "type": "twin-state",
    "twinId": "project5-xxxxx",
    "generatedAt": "2025-11-01T02:15:00.000Z",
    "hosts": [
      {
        "hostname": "core-switch",
        "ip": "10.0.0.1",
        "status": "online",
        "metrics": { "cpuLoad": 12.5, "memoryUsedPercent": 18.2 },
        "position": { "x": 0, "y": 0, "z": 0 }
      }
    ],
    "links": [
      {
        "id": "core-switch::titan-01",
        "source": "core-switch",
        "target": "titan-01",
        "throughputGbps": 4.2,
        "utilization": 0.52
      }
    ]
  }
  ```

## 현재 구현된 모듈
- **MetricsModule**: Zod 검증을 통과한 샘플을 수집하여 디지털 트윈 엔진에 전달
- **DigitalTwinModule**: 호스트 상태를 추적하고 BehaviorSubject로 스냅샷을 전파, Socket.IO 게이트웨이와 REST 컨트롤러 제공
- **HealthController**: 간단한 헬스 체크

구체적인 설계/데이터 모델은 최상위 `docs/` 디렉터리(특히 `architecture.md`)와 동기화합니다.
