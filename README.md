# MIRROR STAGE (거울단계)

10.0.0.0/24 내부망에 연결된 모든 PC와 서버를 한눈에 모니터링하고 제어하기 위한 개인 전용 대시보드입니다. 단일 화면에서 성능 지표, 네트워크 상태, 저장소 사용량, 원격 명령 실행까지 관리할 수 있는 통합 관제 시스템을 목표로 합니다. 프로젝트 코드명은 **MIRROR STAGE**, 한국어 명칭은 **거울단계**이며 지휘본부 서비스는 **EGO**, 각 호스트 에이전트는 **REFLECTOR**로 구분합니다.

## 1. 핵심 목표
- 내부망(10.0.0.0/24) 상의 모든 호스트 CPU·메모리·GPU·스토리지·온도·네트워크 실시간 조회
- 시계열 데이터 보관 및 트렌드 분석, 이상 징후 감지
- 네트워크 토폴로지와 물리적 배치를 반영한 미러월드급 2D/3D 시각화 제공
- 원격 명령 실행, 서비스 재시작, Wake-on-LAN 등 제어 기능
- 임계치 기반 알림(데스크톱/모바일/메신저), 에이전트 연결 끊김 감지
- 사용자/권한 관리 및 안전한 원격 터널링

## 2. 전체 아키텍처 개요
```
┌──────────────┐      ┌──────────────────┐      ┌───────────────┐
│ 에이전트(호스트별) │ ---> │ 수집 게이트웨이/API │ ---> │ 시계열 데이터베이스 │
│                  │ <--- │  + 명령 버스        │ <--- │  + 오브젝트 스토리지 │
└─────┬──────────┘      └───────┬──────────┘      └───────┬──────────┘
      │                          │                        │
      │ REST / gRPC + MQTT       │ GraphQL / REST          │
      ▼                          ▼                        ▼
┌────────────────────────────────────────────────────────────┐
│             대시보드 프런트엔드 (Flutter Web/Desktop/Mobile) │
└────────────────────────────────────────────────────────────┘
```
- **에이전트**: 각 호스트에 설치되는 Python/Rust 기반 경량 데몬. 수집한 헬스 메트릭 전송, 명령 수신·실행, 구조화 로그 전송.
- **수집 레이어**: TypeScript(NestJS) 기반. WebSocket/MQTT 브리지로 실시간 업데이트 처리, 인증·검증 후 저장소로 전달.
- **명령 버스**: MQTT 또는 NATS 기반 퍼블리시/구독. 개별 호스트 대상 명령과 전체 브로드캐스트 지원.
- **스토리지**:
  - TimescaleDB(또는 InfluxDB)로 메트릭 저장.
  - PostgreSQL로 자산/사용자/자동화 메타데이터 관리.
  - MinIO/S3 호환 스토리지로 로그·스냅샷 등 파일 보관.
- **프런트엔드**: Flutter 기반 반응형 UI. 하나의 코드베이스로 Web/데스크톱/모바일(안드로이드·iOS) 지원, 실시간 그래프는 Syncfusion charts 또는 fl_chart 검토. 네트워크 미러월드 구현을 위해 `three_dart`, `flutter_cube`, Impeller 기반 커스텀 쉐이더 또는 WebGL(three.js) 브리지를 활용한 3D 장면 렌더링을 병행.

## 3. 서비스 레이아웃 (EGO vs REFLECTOR)
```
/mirror_stage
├── ego/                       # 10.0.0.100 지휘본부(EGO) 자산
│   ├── backend/               # NestJS(TypeScript) 수집/명령 게이트웨이
│   ├── frontend/              # Flutter Web/Desktop/Mobile 디지털 트윈 뷰어
│   └── docs/                  # 설계 문서, API/프로토콜, ADR
└── reflector/                 # 10.0.0.x 호스트 배포용 REFLECTOR 에이전트
    ├── src/                   # Python 수집기 및 업링크 루프
    ├── config.json            # 기본 구성 템플릿
    ├── start_reflector.sh     # 백그라운드 실행 스크립트
    └── logs/…                 # 에이전트 운영 로그 (실행 후 생성)
```

## 4. 자동 설치 스크립트
- **EGO (지휘본부)**
  ```bash
  curl -fsSLo install_ego.sh https://raw.githubusercontent.com/DARC0625/MIRROR_STAGE/main/scripts/install_ego.sh
  bash install_ego.sh ~/mirror_stage_ego
  ```
- **REFLECTOR (호스트 에이전트)**
  ```bash
  curl -fsSLo install_reflector.sh https://raw.githubusercontent.com/DARC0625/MIRROR_STAGE/main/scripts/install_reflector.sh
  bash install_reflector.sh ~/mirror_stage_reflector
  ```
  > 기본 저장소 URL은 `MIRROR_STAGE_REPO`, 브랜치는 `MIRROR_STAGE_BRANCH` 환경변수로 덮어쓸 수 있습니다.

- **Windows 설치 프로그램(EGO)**
  - GitHub Actions(`.github/workflows/build-ego-installer.yml`)이 Inno Setup을 이용해 `mirror-stage-ego-setup.exe`를 빌드합니다.
  - 릴리스 태그 `ego-v*`를 푸시하거나 워크플로를 수동 실행하면 설치 프로그램이 생성되어 아티팩트로 제공됩니다.
  - 설치 파일은 `packaging/install-mirror-stage-ego.ps1`을 실행해 **번들된 EGO 백엔드/프런트엔드 소스**를 풀고, 부족한 경우 Node.js·Flutter SDK를 자동으로 내려받아 `%LOCALAPPDATA%\MIRROR_STAGE\tools` 아래에 배치합니다. 이후 `npm ci` + `npm run build`, `flutter build web` 을 수행해 런타임에 필요한 산출물을 미리 생성합니다.
  - 기본 설치 경로: `%LOCALAPPDATA%\MIRROR_STAGE`. 설치가 끝나면 EGO 런처가 자동으로 실행되며(After-install run), 시작 메뉴와 선택한 경우 바탕화면 아이콘에서도 `Launch MIRROR STAGE EGO`로 접근할 수 있습니다.
  - 설치 진행은 Inno Setup 진행 페이지 하단에 실시간 로그/상태 메시지로 표시됩니다. Node.js 다운로드 → Flutter 다운로드/압축 해제 → `npm ci`/`npm run build` → `flutter build web` 순서를 확인할 수 있으며 별도의 PowerShell 창은 더 이상 뜨지 않습니다.
  - 설치/런처 로그는 `%LOCALAPPDATA%\MIRROR_STAGE\logs` 아래 `install-YYYYMMDD-HHMMSS.log`, `launcher-YYYYMMDD-HHMMSS.log` 로 남습니다. 문제 발생 시 해당 로그와 설치 화면의 기록을 함께 확인하면 의존성 다운로드 실패, 빌드 오류 등의 원인을 빠르게 파악할 수 있습니다.

### 개발용 2.5D 디지털 트윈 미리보기
- EGO 백엔드를 실행한 뒤 샘플 메트릭을 주입하면 Flutter 2.5D 네트워크 뷰를 즉시 확인할 수 있습니다.
- 개발용 시더: `node scripts/dev_seed_metrics.mjs`
  - 기본 대상: `http://localhost:3000/api/metrics/batch`
  - `--once` 옵션으로 단일 배치 전송, 기본은 5초 주기 루프
  - `MIRROR_STAGE_METRICS_URL`, `MIRROR_STAGE_SEED_INTERVAL_MS` 환경변수로 엔드포인트·주기 오버라이드
- 8개의 가상 호스트가 랙/좌표와 함께 생성되며 CPU·메모리·네트워크 지표를 주기적으로 변화시켜 2.5D 레이아웃, 링크 색상 변화를 빠르게 체험할 수 있습니다.
- EGO 백엔드 메트릭은 TypeORM을 통해 SQLite(`mirror_stage.db`)에 기본 저장됩니다. TimescaleDB/PostgreSQL 사용 시 `MIRROR_STAGE_DB_URL` 환경변수를 지정하세요.
## 5. 인프라 부트스트랩
- `docker-compose.yml`을 통해 TimescaleDB + Redis 개발 환경을 1분 안에 띄울 수 있습니다.
  ```bash
  cp .env.example .env             # 필요 시 환경변수 수정
  docker compose up -d timescaledb redis
  ```
- NestJS 백엔드는 `MIRROR_STAGE_DB_URL`/`MIRROR_STAGE_REDIS_URL`을 참조해 TimescaleDB·Redis에 자동 연결합니다. 기본값은 로컬 `postgresql://mirror_stage:mirror_stage_password@localhost:5432/mirror_stage`, `redis://localhost:6379` 입니다.
- TimescaleDB는 `timescaledb_data` 볼륨, Redis는 `redis_data` 볼륨에 영속화됩니다.

## 6. 실시간 데이터 품질 강화
- **EGO 자가 모니터링**: `EgoMonitorService`가 `systeminformation` 기반으로 EGO 서버의 CPU·메모리·네트워크 용량을 1초~5초 간격으로 수집합니다. `MIRROR_STAGE_EGO_MONITOR_ENABLED/INTERVAL_MS` 환경변수로 제어할 수 있습니다.
- **REFLECTOR v0.2**: 에이전트가 인터페이스 속도, 패킷 에러, 디스크 사용량, 센서 온도 등을 함께 전송하며 `tags.primary_interface_speed_mbps`에 링크 용량을 명시합니다.
- **링크 활용률 모델**: Digital Twin 엔진이 각 호스트의 누적 바이트와 타임스탬프를 비교해 Gbps 단위 스루풋과 용량 대비 활용률을 계산, 링크 두께·색상에 반영합니다.
- **임계치 알람**: CPU/메모리/온도/링크 혼잡도를 감시해 `GET /api/alerts/active`에서 조회 가능한 알람으로 승격합니다. 추후 ML 기반 이상탐지로 확장 예정입니다.
- **REFLECTOR 명령 루프(초기 버전)**: `command_endpoint`가 설정된 에이전트는 명령 큐를 폴링하고, 실행 결과(stdout/stderr/exitCode)를 보고합니다.
- **명령 파이프라인**: `POST /api/commands`로 명령을 등록하면 REFLECTOR가 `GET /api/commands/pending/:hostname`을 통해 가져가고, `POST /api/commands/:id/result`로 실행 결과를 보고합니다. Socket.IO(`ws://<EGO>:3000/commands`)에서 `command-update` 이벤트로 실시간 상태를 구독할 수 있습니다.
- **설치 로그 텔레메트리**: Windows 설치 PowerShell 스크립트가 명령 실행 경로·명령줄·stdout/stderr를 실시간으로 로그와 진행 파일에 기록해 문제 분석을 용이하게 합니다.

## 7. 필수/권장 사전 준비 사항
- Node.js 20.x (EGO 백엔드). 예: `curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt-get install -y nodejs`
- Flutter 3.35.5 이상 또는 FVM (EGO 프런트엔드)
- Python 3.12 + `python3-venv` (REFLECTOR)

## 8. 초기 MVP 범위
1. **인벤토리**: 호스트 등록, 메타데이터 저장, 목록/상세 UI.
2. **메트릭 수집**: 에이전트가 5초마다 CPU·메모리·로드 전송 → 백엔드 검증 후 TimescaleDB 적재.
3. **실시간 대시보드**: 테이블+스파크라인 UI, WebSocket으로 즉시 갱신.
4. **명령 실행**: 임의 호스트에 `uptime`과 같은 명령 전달, stdout/stderr 수집 및 표시.
5. **인증**: 단일 사용자 로그인(TOTP) + 에이전트용 API 토큰.

## 9. 보안 및 네트워킹
- 에이전트 ↔ 게이트웨이 상호 TLS, 인증서 자동 갱신
- 주제(topic) 단위 권한 제어, 호스트별 자격 증명
- Vault 호환 비밀 관리(개발 단계에서는 dotenv 사용)
- 모든 명령과 결과에 대한 감사 로그

## 10. 단기 로드맵
1. 백엔드/프런트엔드/에이전트 디렉터리 스캐폴딩 및 devcontainer·docker-compose 구성
2. `HostMetrics`, `CommandRequest`, `CommandResult`용 protobuf/OpenAPI 스키마 정의
3. 백엔드 뼈대 구현:
   - NestJS + Prisma(or TypeORM) + PostgreSQL/TimescaleDB
   - WebSocket 게이트웨이 및 MQTT 브리지
   - Redis/NATS 기반 백그라운드 워커(예: BullMQ)
4. 에이전트 MVP 개발(Python):
   - `psutil`, `nvidia-smi`, `smartctl` 등으로 메트릭 수집
   - HTTPS/MQTT 전송, 명령 수신 시 샌드박스 실행 후 결과 반환
5. 프런트엔드 UI 쉘 구축(Flutter: Web + 데스크톱 레이아웃, 모바일 반응형 포함)
6. 네트워크 토폴로지·공간 데이터 스키마 정의 및 미러월드 3D 뷰 프로토타입 제작
7. 로컬 멀티 호스트 시뮬레이션용 docker-compose 시나리오 추가

## 11. 다음 액션 체크리스트
- [ ] TimescaleDB vs InfluxDB 최종 결정
- [ ] `docs/api-contracts.md`에 상세 API/큐 명세 작성
- [ ] pre-commit 훅(ruff, black, eslint, prettier 등) 구성
- [ ] 신규 호스트 에이전트 온보딩 가이드 정리
- [ ] 테스트 호스트 1대로 메트릭 수집 엔드투엔드 검증
- [ ] 네트워크 장비 위치/케이블/레이블 정보를 위한 디지털 트윈 메타데이터 스키마 확정

## 12. 환경 관리 원칙
- **EGO 백엔드(NestJS)**: 설치 프로그램이 Node 20.x 런타임을 `%LOCALAPPDATA%\MIRROR_STAGE\tools\node`(또는 사용자가 지정한 루트) 아래에 내려받아 `npm ci`, `npm run build`를 수행합니다. 런처는 `node dist/main.js`를 실행해 정적 자산과 API를 동시에 제공합니다.
- **EGO 프런트엔드(Flutter)**: 배포 시 `flutter build web` 결과물을 `frontend/build/web`에 생성해 백엔드에서 정적 제공하므로, 운영 시에는 Flutter SDK가 필요하지 않습니다. UI 개발/커스터마이징이 필요할 때만 FVM 또는 `%LOCALAPPDATA%\MIRROR_STAGE\tools\flutter` SDK를 사용해 다시 빌드합니다.
- **REFLECTOR 에이전트(Python)**: `mirror_stage/reflector` 에 전용 가상환경(`python3 -m venv .venv`). 활성화 상태에서만 패키지 설치 및 스크립트 실행. 각 10.0.0.x 호스트에 배포 시 동일 구조 유지.
- 각 서브 프로젝트는 독립적인 커밋 히스토리로 의존성 변경을 추적하며, 전역 패키지 설치나 시스템 Python 사용은 금지.
- 공통 도구(예: pre-commit, lint 스크립트)는 `scripts/`에 배치하고 README에 실행 절차 명시.

---
현재는 설계 문서 중심으로 시작하며, 스택이 확정되면 백엔드·프런트엔드·에이전트 기본 구조를 추가 커밋으로 정리할 예정입니다.
