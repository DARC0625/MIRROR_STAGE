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

## 5. 초기 MVP 범위
1. **인벤토리**: 호스트 등록, 메타데이터 저장, 목록/상세 UI.
2. **메트릭 수집**: 에이전트가 5초마다 CPU·메모리·로드 전송 → 백엔드 검증 후 TimescaleDB 적재.
3. **실시간 대시보드**: 테이블+스파크라인 UI, WebSocket으로 즉시 갱신.
4. **명령 실행**: 임의 호스트에 `uptime`과 같은 명령 전달, stdout/stderr 수집 및 표시.
5. **인증**: 단일 사용자 로그인(TOTP) + 에이전트용 API 토큰.

## 6. 보안 및 네트워킹
- 에이전트 ↔ 게이트웨이 상호 TLS, 인증서 자동 갱신
- 주제(topic) 단위 권한 제어, 호스트별 자격 증명
- Vault 호환 비밀 관리(개발 단계에서는 dotenv 사용)
- 모든 명령과 결과에 대한 감사 로그

## 7. 단기 로드맵
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

## 8. 다음 액션 체크리스트
- [ ] TimescaleDB vs InfluxDB 최종 결정
- [ ] `docs/api-contracts.md`에 상세 API/큐 명세 작성
- [ ] pre-commit 훅(ruff, black, eslint, prettier 등) 구성
- [ ] 신규 호스트 에이전트 온보딩 가이드 정리
- [ ] 테스트 호스트 1대로 메트릭 수집 엔드투엔드 검증
- [ ] 네트워크 장비 위치/케이블/레이블 정보를 위한 디지털 트윈 메타데이터 스키마 확정

## 9. 환경 관리 원칙
- **EGO 백엔드(NestJS)**: `mirror_stage/ego/backend` 내에 Node 20.18.0 바이너리가 동봉(`.node/`). `export PATH="$(pwd)/ego/backend/.node/bin:$PATH"` 후 `npm install` 실행. 지휘 서버(10.0.0.100)에서만 동작.
- **EGO 프런트엔드(Flutter)**: `mirror_stage/ego/frontend` 디렉터리에서 FVM으로 Flutter 3.35.5 고정. `fvm flutter run -d web-server …`로 8080 포트에 띄우고, Control Plane에서 운영.
- **REFLECTOR 에이전트(Python)**: `mirror_stage/reflector` 에 전용 가상환경(`python3 -m venv .venv`). 활성화 상태에서만 패키지 설치 및 스크립트 실행. 각 10.0.0.x 호스트에 배포 시 동일 구조 유지.
- 각 서브 프로젝트는 독립적인 커밋 히스토리로 의존성 변경을 추적하며, 전역 패키지 설치나 시스템 Python 사용은 금지.
- 공통 도구(예: pre-commit, lint 스크립트)는 `scripts/`에 배치하고 README에 실행 절차 명시.

---
현재는 설계 문서 중심으로 시작하며, 스택이 확정되면 백엔드·프런트엔드·에이전트 기본 구조를 추가 커밋으로 정리할 예정입니다.
