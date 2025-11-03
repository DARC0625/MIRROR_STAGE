# Architecture Overview

## Components

### 1. Host Agent
- Written in Python 3.12 for portability; Rust rewrite when performance-critical.
- Collectors:
  - CPU: load avg, per-core utilization, frequency.
  - Memory: total/available/swap.
  - Disk: per-mount usage, IOPS, SMART health.
  - GPU: NVIDIA stats via `nvidia-smi` (fallback to ROCm/Intel support later).
  - Network: per-interface throughput, errors, latency to configurable targets.
  - Link capacity: export NIC speed/duplex as `tags.primary_interface_speed_mbps` for 활용률 계산.
  - Processes: top-k resource consumers.
- Scheduler emits payload every 5s (configurable).
- Command executor:
  - Pulls instructions from MQTT topic `agents/{hostname}/commands`.
  - Executes within confined shell (optionally firejail/sandbox).
  - Streams stdout/stderr back via gRPC streaming or MQTT `responses` topic.
- Self-update capability via signed bundles to simplify rollout.

### 2. Ingestion Gateway (API)
- NestJS (TypeScript) running on Node 20 with `@nestjs/platform-fastify`.
- Endpoints:
  - `POST /api/v1/hosts/register`
  - `POST /api/v1/metrics/batch`
  - `POST /api/v1/events`
  - `POST /api/v1/commands/{id}/result`
- Uses JWT for agent auth; tokens minted via CLI after certificate exchange.
- Validates payloads with class-validator/class-transformer; rejects stale timestamps or duplicate sequence IDs.
- Publishes normalized metrics into NATS subjects: `metrics.raw`, `metrics.normalized`.
- Applies per-host rate limits (token bucket) to guard against runaway agents.

### 3. Command Bus
- NATS JetStream (lightweight, durable).
- Subjects:
  - `commands.pending`: dashboard publishes command requests with metadata.
  - `commands.dispatch.{hostname}`: gateway fans out to targeted agent.
  - `commands.result`: agent responses captured for auditing.
- Retains command history 30 days, move to cold storage afterwards.

### 4. Storage
- TimescaleDB:
  - Table `metrics_cpu`, `metrics_memory`, `metrics_network`, `metrics_disk`.
  - Hypertables partitioned per host, compression after 7 days.
- PostgreSQL (core):
  - `hosts`, `host_groups`, `users`, `roles`, `automations`, `alerts`.
  - Use Prisma ORM (with TimescaleDB plugin) or TypeORM for schema management and migrations.
- Redis:
  - Caching latest snapshot for fast dashboard render.
  - Stores WebSocket session info and pub/sub for UI notifications.
- Object Storage:
  - MinIO in self-hosted mode for logs, agent bundles, config backups.

### 5. Frontend Dashboard
- Flutter 3.x with AdaptiveLayout to support Web, 데스크톱, 모바일.
- Real-time updates via `web_socket_channel` + Riverpod(or Bloc) state management.
- 3D 미러월드 장면: `three_dart`/`flutter_cube`/Impeller 커스텀 렌더러 기반으로 랙/룸 배치, 링크 상태, 대역폭을 실감나게 표현. Web 빌드에서는 three.js 캔버스를 PlatformView로 임베드하는 옵션도 검토.
- 주요 화면:
  - `OverviewScreen`: 전체 상태, 알람, 상위 리소스 사용 호스트.
  - `HostsScreen`: 필터 가능한 목록 및 인라인 스파크라인.
  - `HostDetailScreen`: 타임라인 차트, 명령 히스토리, 자동화 트리거.
  - `NetworkScreen`: 2D/3D 토폴로지 뷰 (graphview · flutter_graphviz + 3D 미러월드 씬 하이브리드).
  - `AutomationScreen`: 시나리오 정의 및 스케줄 UI.
- 반응형 레이아웃으로 모바일에서는 주요 카드/차트 우선 표시, 데스크톱에서는 테이블+차트 동시 노출.
- Auth flow는 JWT + refresh 토큰, `dio` 인터셉터로 토큰 갱신.

### 6. Digital Twin Engine
- NestJS 내 독립 모듈 또는 별도 마이크로서비스로 구현.
- 자산 데이터(랙/룸 좌표, 장비 치수, 케이블 경로)와 실시간 메트릭을 결합해 3D 장면용 그래프 모델을 생성.
- 레이아웃 계산:
  - 2D 토폴로지는 `force-directed` 알고리즘으로 정규화.
  - 3D 공간은 사전 정의된 좌표(서버 룸 맵) + 실시간 위치 업데이트.
- 씬 빌더는 JSON 혹은 glTF 포맷으로 Flutter 앱에 전달, 장비 상태(온도, 대역폭, 알람)를 머티리얼 속성으로 인코딩.
- 장면 변화 발생 시 이벤트 큐(`visualization.updates`)로 diff를 발행, 클라이언트는 부분 업데이트만 적용.
- 링크 활용률 계산: 호스트 누적 바이트 + 링크 속도를 비교해 Gbps/Utilization을 산출, 링크 두께·색상으로 가시화.

## Data Flow (Happy Path)
1. Agent collects metrics → signs payload → POST `/metrics/batch`.
2. Gateway validates → persists to TimescaleDB → updates Redis cache → emits WebSocket/SSE event.
3. Digital Twin Engine consumes metrics/인벤토리 이벤트 → 최신 토폴로지/장비 상태를 계산 → glTF/JSON diff 생성.
4. Flutter 앱(Web/모바일)이 이벤트를 수신 → 상태 갱신 후 카드/차트 및 3D 씬을 재렌더링.
5. User issues command via UI → backend stores command in Postgres → publishes to `commands.pending`.
6. Worker picks up → routes to `commands.dispatch.hostname`.
7. Agent executes → publishes to `commands.result` → backend records output and notifies UI.

## Observability
- OpenTelemetry instrumentation via `@opentelemetry/sdk-node` + NestJS interceptor, exported to Grafana Tempo.
- Prometheus scraping for all services (gateway, workers, db).
- Centralized logs via Loki; correlate with command IDs.
- Flutter 클라이언트는 Sentry(or Firebase Crashlytics)로 오류 수집, analytics는 self-hosted Plausible 검토.
- Digital Twin Engine은 렌더 주기, 메시지 래그, FPS 등 시각화 메트릭을 Prometheus 커스텀 지표로 노출.

## Deployment Targets
- Local development: `docker compose up` with TimescaleDB, Redis, NATS, MinIO.
- Production: Kubernetes (k3s) per home lab cluster, GitOps with ArgoCD.
- Agents packaged as Debian/RPM, Windows service, systemd units.

## Outstanding Decisions
- Choose secrets management (HashiCorp Vault vs Doppler).
- Evaluate gRPC (better streaming) vs HTTP + MQTT for commands.
- Determine Flutter 차트/그래프 라이브러리 (Syncfusion, fl_chart, charts_flutter).
- Pick notification integration (NTFY, Telegram, Slack).
- Decide on 3D 미러월드 렌더링 파이프라인 (纯 Flutter vs WebGL 임베드 vs 외부 엔진 연동).

Document will evolve as prototypes land. Update with ADRs for major decisions.
