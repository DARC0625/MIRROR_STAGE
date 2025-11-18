# MIRROR STAGE

> 내부망 노드들을 고해상도 디지털 트윈으로 투영하고, 실시간 텔레메트리·명령·알람을 한 화면에서 다루는 개인 전용 관제 시스템입니다. 코드명 **EGO**(지휘 본부) + **REFLECTOR**(호스트 에이전트) 조합으로 동작합니다.

## 현재 구현 상태 한눈에 보기
- **메트릭 파이프라인**: Python REFLECTOR가 psutil로 수집한 CPU/메모리/온도/디스크/네트워크 데이터를 `POST /api/metrics/batch`로 전송하면 NestJS MetricsService가 TypeORM 엔티티(HostMetricEntity, HostMetricSampleEntity)에 저장하고, 디지털 트윈 스트림과 AlertsService에 동시에 전달합니다.
- **디지털 트윈 스트림**: `DigitalTwinService`가 호스트 상태를 메모리에 유지하며 BehaviorSubject로 스냅샷을 전파합니다. WebSocket 게이트웨이(`/digital-twin`)와 REST 엔드포인트(`/api/twin/state`) 모두 같은 스냅샷을 제공합니다.
- **명령/경보/자가 모니터링**: CommandsService가 큐+History+RxJS 스트림을 제공하고, AlertsService는 CPU/메모리/링크 혼잡 임계치를 평가합니다. EgoMonitorService는 EGO 서버 자체를 시스템정보(systeminformation)로 수집해 동일 파이프라인에 재주입합니다.
- **HUD(frontend)**: Flutter 3.35 기반 `main.dart`가 TwinChannel(socket.io) 스트림을 수신해 2.5D OSI 계층 맵(_TwinScenePainter)과 좌/우 4×N 위젯 도킹 시스템을 그립니다. Pretendard 폰트, WebGL 없이 Canvas + 커스텀 painter로 구현되었습니다.
- **설치/포장**: `packaging/install-mirror-stage-ego.ps1`는 모든 의존성을 설치/빌드하는 메인 스크립트이고, `packaging/msix/build_msix.ps1`가 MSIX 레이아웃을 만들어 WinGet/MSIX 배포 파이프라인에 투입합니다. 부팅은 `start_ego.ps1`로 수행합니다.

## 디렉터리 구조
```
mirror_stage/
├── ego/
│   ├── backend/   # NestJS API, WebSocket, digital twin, DB/알람/명령 모듈
│   ├── frontend/  # Flutter HUD (web/desktop/mobile 대응)
│   └── docs/      # 설계/ADR 초안들
├── reflector/     # Python REFLECTOR agent (telemetry + command loop)
├── packaging/     # Windows 설치 스크립트(MSIX/WinGet + PowerShell)
├── assets/        # Pretendard 등 프런트 자산
├── scripts/       # 배포/진단용 유틸리티
└── docker-compose.yml # 로컬 개발용 Postgres/Redis 샘플
```

## EGO 백엔드 (NestJS + TypeORM)
### 핵심 모듈
| 모듈 | 주요 파일 | 설명 |
| --- | --- | --- |
| Metrics | `src/metrics/*` | ZodValidationPipe로 `POST /api/metrics/batch` 페이로드를 검증 후 `MetricsService.ingestBatch`에 전달. 샘플당 HostMetricEntity(스냅샷)와 HostMetricSampleEntity(히스토리)를 동시 저장. AlertsService와 DigitalTwinService에 동일 샘플을 주입. |
| Digital Twin | `src/twin/*` | DigitalTwinService가 HostState Map을 유지. Golden-angle 기반 위치 계산 + OSI 계층 배치, 네트워크 용량 추정(`extractCapacityGbps`), 전송량 차분으로 throughput 계산 후 CPU 부하 기반 정규화(`normalizeThroughput`). BehaviorSubject → DigitalTwinGateway(WebSocket) + Controller(REST). |
| Commands | `src/commands/*` | CommandEntity를 TypeORM으로 관리. `GET /api/commands/pending/:hostname` 호출 시 pending→running 전환하여 중복 실행 방지, 결과 업로드 시 status/로그 저장. RxJS Subject로 상태 브로드캐스트. |
| Alerts | `src/alerts/*` | 임계치 기반 경보(`handleThreshold`)와 링크 혼잡(`handleThroughput`). 활성 AlertEntity만 조회/업데이트, resolved 처리 자동화. |
| Ego Monitor | `src/ego-monitor/*` | 시스템정보(si) + OS API로 EGO 서버 자체 메트릭을 수집, primary NIC 속도/온도/탑 프로세스 등 REFLECTOR와 동일 스키마로 MetricsService에 주입. SchedulerRegistry로 주기 실행 관리. |
| Cache | `src/cache/cache.module.ts` | Redis URL 존재 시 redisStore, 없으면 cache-manager memory store. DigitalTwinService.persistSnapshot 등에서 직렬화 캐시에 활용 가능. |

### 데이터베이스
- TypeORM이 환경에 따라 Postgres(`MIRROR_STAGE_DB_URL`) 또는 SQLite 파일/메모리(테스트)로 자동 전환.
- 엔티티: `HostMetricEntity`, `HostMetricSampleEntity`, `CommandEntity`, `AlertEntity` 등. 모두 `synchronize: true`로 스키마 자동 생성.

### 공개 API 요약 (모두 `/api` prefix)
| 메서드 | 경로 | 내용 |
| --- | --- | --- |
| `GET /health` | 헬스 체크 문자열 "ok" 반환. |
| `POST /metrics/batch` | REFLECTOR 샘플 배열 수신. 응답에 `accepted` 개수와 타임스탬프 포함. |
| `GET /twin/state` | 최신 디지털 트윈 스냅샷(JSON). |
| `GET /alerts/active` | 활성 AlertEntity 리스트. |
| `POST /commands` | 명령 생성. hostname/command/timeoutSeconds. |
| `GET /commands` | hostname/status/search/page 파라미터로 이력 페이지네이션. |
| `GET /commands/pending/:hostname` | 에이전트용 대기 명령 리스트 (호출 시 running 전환). |
| `POST /commands/:id/result` | 실행 결과 업로드(status, stdout/stderr, exitCode 등). |
| WebSocket `wss://.../digital-twin` | `twin-state` 이벤트로 BehaviorSubject 프레임 푸시. 클라이언트 접속 시 즉시 1회 push. |

## EGO 프런트엔드 (Flutter 3.35)
### 데이터 소스
- `core/services/twin_channel.dart`: socket.io-client 기반 WebSocket. 연결 실패 시 지수 백오프+지터 `_scheduleReconnect`. `TwinStateFrame` 디코딩 로직은 모델(`core/models/twin_models.dart`)에 정의.
- `core/services/command_service.dart`: REST API 클라이언트. hostname/status/search/page를 쿼리스트링으로 구성해 명령 페이지를 받아오고, 명령 생성도 담당.

### HUD 개요 (lib/main.dart)
- `DigitalTwinShell`가 TwinChannel 스트림을 구독해 `_TwinStage`(중앙 맵)와 좌/우 사이드바 위젯에 전달.
- `_WidgetDockController`: 좌/우 각각 4×10 격자. Blueprint(`_widgetBlueprints`)에 따라 각 위젯의 가로/세로 유닛을 정의하고, 드래그 앤 드롭 시 충돌 검사(`canPlace`). 한 타입은 한 번만 도킹.
- `_WidgetGridPanel`: 격자 배경 + 드래그 미리보기(`_DropIndicator`). `_GridSpec`이 픽셀 크기를 계산해 모든 위젯이 스크롤 없이 노출되도록 함.
- 좌측 위젯: 글로벌/선택 노드 메트릭, 링크 상태, 온도, 명령 콘솔. 빈 공간 클릭 시 글로벌, 노드 선택 시 해당 노드 메트릭으로 자동 전환.
- 우측 위젯: 프로세스 패널(3개씩 슬라이드), 네트워크 인터페이스(2개씩), 스토리지(2개씩). `_PageDots`와 `_chunkList`로 슬라이드 형태 구현.
- `_TwinStage` + `_TwinViewport`: 마우스/터치 팬·줌, 레이어 focus 토글, 노드 드래그(OSI 계층 이동), 중앙화 카메라 트래킹 지원. 줌/팬 값은 clamp되어 렌더링 영역 밖으로 나가지 않음.
- `_TwinScenePainter`: Canvas 2.5D 렌더러.
  - 골든앵글 씨앗 + 계층별 그리드로 기본 좌표 계산.
  - `_kDefaultOsiLayers`(1~7) 판을 컬러코딩해 샌드위치 구조로 배치.
  - 링크는 throughput 활용 색/굵기, `_linkPulse` 값으로 흐르는 듯한 애니메이션.
  - 선택한 노드는 hologram 패널을 화면 옆에 띄워 OS/버전/CPU/GPU/메모리 등을 표시.
  - 카메라 이동은 두 포지션 보간(TwinPosition.lerp) + easeOutCubic easing.
- Pretendard 폰트를 assets/fonts에서 로드해 전체 UI에 적용.

## REFLECTOR 에이전트 (Python 3.11)
- `agent/telemetry.py`: psutil로 CPU 로드, per-core, 메모리(total/available), loadavg, uptime, 네트워크 byte counter, 디스크 사용, 인터페이스 속도, 온도 센서, 상위 프로세스, uname 정보를 수집. 센서 미보고 시 graceful fallback. config.json의 태그/위치/호스트명 override와 merge.
- `agent/runtime.py`: asyncio 기반. `telemetry_loop`는 interval backoff + failure counter를 갖추고, `command_loop`는 polling 주기마다 pending 명령을 받아 `CommandExecutor`로 실행.
- `agent/transport.py`: metrics용 HttpTransport, 명령용 CommandTransport(`GET /commands/pending/:hostname`, `POST /commands/result/:id`).
- `agent/commands.py`: subprocess.run으로 명령 실행, stdout/stderr 4KB만 저장, timeout/에러 상태 구분.
- `start_reflector.sh`: venv 활성화 후 `python -m agent.main` 실행. `--once` 옵션으로 JSON 페이로드 출력 지원.
- 설정(`reflector/config.json`): endpoint, command_endpoint, interval_seconds, rack, position{x,y,z}, tags 등을 정의.

## 데이터 흐름
1. **수집**: REFLECTOR 또는 EgoMonitor가 샘플 JSON을 업링크 → `POST /api/metrics/batch`.
2. **저장/스트림**: MetricsService가 TypeORM save + AlertsService.evaluateSample + DigitalTwinService.ingestSample 호출.
3. **디지털 트윈 가공**: DigitalTwinService는 HostState map 업데이트, throughput/온도/하드웨어/계층 정보 구성, BehaviorSubject로 전체 스냅샷 발행.
4. **UI 반영**: Flutter TwinChannel이 `twin-state` 이벤트를 받아 `_TwinStage`와 위젯에 전파. 사용자가 명령을 제출하면 CommandService가 REST로 전송, CommandsService는 DB+updatesSubject로 기록.
5. **에이전트 명령 실행**: REFLECTOR CommandExecutor가 pending 요청을 받아 subprocess 실행 후 결과 업로드.

## 빌드 및 실행
### 사전 준비
- Node.js 20.x (설치 스크립트는 자체 번들 Node를 내려받지만 로컬 개발은 시스템 Node 사용 가능)
- pnpm/npm 중 선택 (repo는 npm lock). `npm ci` 권장.
- Flutter 3.35.7 (installer는 tools 디렉터리에 내려받음). 개발 시 `flutter doctor`로 환경 구성.
- Python 3.11 + venv (REFLECTOR).

### 백엔드 (NestJS)
```bash
cd ego/backend
npm ci
npm run start:dev   # 개발
npm run build && npm run start:prod  # 배포 번들
```
환경 변수:
- `MIRROR_STAGE_DB_URL`: Postgres 연결 문자열. 미설정 시 SQLite 파일(`mirror_stage.db`).
- `MIRROR_STAGE_REDIS_URL`: 캐시용 Redis. 없으면 in-memory cache.
- `MIRROR_STAGE_EGO_MONITOR_ENABLED`: `false`면 자체 모니터 비활성화.
- `EGO_HOSTNAME`, `EGO_DISPLAY_NAME`, `EGO_RACK`: EgoMonitor override.

### 프런트엔드 (Flutter)
```bash
cd ego/frontend
flutter pub get
flutter run -d chrome  # 실시간
flutter build web      # 정적 산출물 → backend ServeStatic에서 사용
```
Web 빌드 결과는 `ego/frontend/build/web`에 생성되며 Nest ServeStaticModule이 `/` 루트로 제공.

### REFLECTOR
```bash
cd reflector
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python -m agent.main --config config.json  # 백그라운드 실행 시 systemd/pm2 권장
```
- `config.json`의 `endpoint`는 예: `http://localhost:3000/api/metrics/batch`.
- 명령 루프 사용 시 `command_endpoint`: `http://localhost:3000/api/commands`.
- `--once`로 수집 페이로드를 표준출력 확인 가능.

## 테스트
| 대상 | 명령 |
| --- | --- |
| Nest 단위 테스트 | `npm run test` (Jest) |
| Nest e2e 테스트 | `npm run test:e2e` (`test/app.e2e-spec.ts`가 메트릭→알람→명령 전체 플로우 검증) |
| Flutter 분석 | `flutter analyze` |
| Flutter 테스트 | `flutter test` (현재 기본 widget_test) |
| REFLECTOR lint/test | (구성 예정, psutil 기반이므로 mypy/pylint 적용 가능) |

## 패키징 및 배포
- `packaging/install-mirror-stage-ego.ps1`: Windows에서 실행되는 주 설치 스크립트. `%LOCALAPPDATA%\MIRROR_STAGE\tools` 아래에 Node/Flutter SDK를 내려받아 `npm ci → npm run build → flutter build web` 순으로 빌드하고 런처(`start_ego.ps1`)를 구성한다.
- `packaging/bundle/build_module_bundles.ps1`: 폐쇄망/오프라인 환경에 대비한 보조 스크립트다. 필요 시 로컬에서 직접 실행해 번들을 만들 수 있지만, 공식 GitHub Actions 파이프라인에서는 더 이상 호출하지 않는다.
- `packaging/launcher/`: 전용 Windows 런처(EXE). 런처 하나로 EGO/REFLECTOR 설치를 모두 수행하며, 기본값으로 `https://www.darc.kr/mirror-stage-latest.zip`(자체 CDN)에 올려둔 소스/스크립트를 **유일한** 공급원으로 사용한다. 필요 시 `launcher-config.json`을 배치하면 다른 URL을 가리킬 수 있지만 GitHub로의 폴백은 존재하지 않는다. `dotnet publish packaging/launcher/MirrorStageLauncher.csproj -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true`로 직접 빌드하거나, [Mirror Stage Launcher 다운로드](https://github.com/DARC0625/MIRROR_STAGE/releases/latest/download/mirror-stage-launcher.zip)를 받아 `MirrorStageLauncher.exe`를 실행하면 된다.
- Release에는 `mirror-stage-launcher.zip`만 포함되며, 런처가 실행 중 GitHub에서 필요한 소스/스크립트를 자동으로 내려받는다. 따라서 릴리스 아셋에 별도 번들을 올릴 필요가 없다.
- WinGet/기업 배포 파이프라인에서는 `build_msix.ps1 -Pack`으로 생성된 MSIX를 업로드하고, WinGet 매니페스트만 작성하면 된다. 필요 시 기존 PowerShell 스크립트만 별도로 실행해 조용히 설치할 수도 있다.

### 런처에서 프런트 서버(자체 CDN) 사용하기
- darc.kr CDN을 관리하려면 `scripts/cdn/update-mirror-stage-cdn.sh`를 서버에 배치해 주기적으로 실행한다. 스크립트는 `git fetch → git reset --hard origin/main → git archive` → `/var/www/html/mirror-stage-latest.zip`/`mirror-stage-version.json`/`mirror-stage-latest.sha` 생성을 자동화한다.
  ```bash
  sudo apt update && sudo apt install -y git nginx jq unzip
  sudo mkdir -p /home/darc/mirror_stage && cd /home/darc/mirror_stage
  git clone https://github.com/DARC0625/MIRROR_STAGE.git repo
  sudo install -m 755 scripts/cdn/update-mirror-stage-cdn.sh /usr/local/bin/update-mirror-stage-cdn.sh
  sudo /usr/local/bin/update-mirror-stage-cdn.sh
  ```
- 실시간에 가깝게 유지하려면 systemd 타이머나 cron으로 스크립트를 호출한다. 예시:
  ```
  # /etc/systemd/system/mirror-stage-cdn.service
  [Unit]
  Description=Sync MIRROR_STAGE archive to darc.kr

  [Service]
  Type=oneshot
  Environment=REPO_DIR=/home/darc/mirror_stage/repo
  Environment=WEB_ROOT=/var/www/html
  ExecStart=/usr/local/bin/update-mirror-stage-cdn.sh
  ```
  ```
  # /etc/systemd/system/mirror-stage-cdn.timer
  [Unit]
  Description=Run MIRROR_STAGE CDN sync frequently

  [Timer]
  OnCalendar=*:0/1
  Persistent=true

  [Install]
  WantedBy=timers.target
  ```
  ```bash
  sudo systemctl daemon-reload
  sudo systemctl enable --now mirror-stage-cdn.timer
  ```
- 런처는 기본적으로 `https://www.darc.kr/mirror-stage-latest.zip` / `https://www.darc.kr/mirror-stage-version.json` 만 사용한다. 다른 CDN을 사용하고 싶을 때에만 `launcher-config.json`으로 URL을 바꿀 수 있다.

## 향후 정비 포인트 (현재 코드 기반)
- AlertsService 임계치/메시지 다국어화 및 사용자 정의 규칙 저장소 추가.
- TwinChannel 스트림 재연결 동안 UI placeholder 제공 및 로컬 시뮬레이터 주입.
- Flutter widget 테스트 확충(위젯 도킹, 명령 생성, 페이지네이션 등).
- REFLECTOR 명령 실행 sandbox/ACL.

---
현재 README는 **실제 커밋된 코드**를 기준으로 작성되었습니다. 문서화되지 않은 기능이나 아직 구현되지 않은 계획은 포함하지 않습니다.
