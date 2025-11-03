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

### 5. 데이터베이스
- 기본 로컬 개발은 sqlite를 통해 동작하지만, `.env`에 `MIRROR_STAGE_DB_URL`을 지정하면 TimescaleDB/PostgreSQL로 자동 전환됩니다.
- `docker compose up -d timescaledb redis`로 TimescaleDB/Redis 개발 클러스터를 띄운 뒤 `MIRROR_STAGE_DB_URL=postgresql://mirror_stage:mirror_stage_password@localhost:5432/mirror_stage`, `MIRROR_STAGE_REDIS_URL=redis://localhost:6379`를 설정하세요.
- 테스트 실행(`npm test`, `npm run test:e2e`) 시에는 자동으로 인메모리 SQLite(`:memory:`)와 메모리 캐시를 사용합니다.

### 6. EGO 자가 모니터링
- `EgoMonitorService`가 `systeminformation` 패키지로 EGO 서버의 CPU/메모리/네트워크 용량을 주기적으로 수집해 백엔드와 디지털 트윈에 반영합니다.
- 기본 주기는 5초이며 `MIRROR_STAGE_EGO_MONITOR_INTERVAL_MS`(최소 1000ms)로 조정, `MIRROR_STAGE_EGO_MONITOR_ENABLED=false` 로 비활성화할 수 있습니다.
- 관측된 링크 용량은 `tags.primary_interface_speed_mbps`와 `host_metrics.net_capacity_gbps`로 저장되어 링크 활용률 계산에 사용됩니다.

## REST API
- `GET /api/health` : 상태 체크(200 ➝ `ok`).
- `POST /api/metrics/batch` : 에이전트가 배치 전송한 메트릭을 수집.
- `GET /api/twin/state` : 현재 디지털 트윈 스냅샷(JSON)
- `GET /api/alerts/active` : 임계치를 초과한 활성 알람 목록
- `POST /api/commands` : 호스트 대상으로 명령을 큐에 등록
- `GET /api/commands/pending/:hostname` : REFLECTOR가 실행 대기 명령을 가져감 (가져가면 `running` 상태로 변경)
- `POST /api/commands/:id/result` : REFLECTOR가 명령 실행 결과(stdout/stderr/exitCode)를 보고
- `GET /api/commands` : 최근 명령 이력 조회

## 실시간 채널
- Socket.IO 네임스페이스: `ws://<host>:3000/digital-twin`
  - 이벤트: `twin-state`
- Socket.IO 네임스페이스: `ws://<host>:3000/commands`
  - 이벤트: `command-update`
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
- **MetricsModule**: Zod 검증을 통과한 샘플을 디지털 트윈 엔진과 TypeORM 리포지토리 양쪽에 반영
- **EgoMonitorModule**: EGO 서버 자체 메트릭을 수집해 Metrics 파이프라인으로 주입
- **DigitalTwinModule**: 호스트 상태를 추적하고 BehaviorSubject로 스냅샷을 전파, Socket.IO 게이트웨이와 REST 컨트롤러 제공
- **AlertsModule**: CPU/메모리/온도/링크 혼잡 임계치를 감시하여 알람을 관리
- **CommandsModule**: REST + Socket.IO로 명령 큐를 관리하고 REFLECTOR와 결과를 주고받음
- **HealthController**: 간단한 헬스 체크

구체적인 설계/데이터 모델은 최상위 `docs/` 디렉터리(특히 `architecture.md`)와 동기화합니다.
