# MIRROR STAGE – Field Agent (거울단계 에이전트)

거울단계(MIRROR STAGE)의 필드 에이전트입니다. 각 호스트에서 메트릭을 수집하고 명령을 실행하며, 지휘본부 EGO로 데이터를 전송합니다.

## 가상환경
```bash
cd reflector
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```
- 항상 `.venv`가 활성화된 상태에서만 패키지를 설치/업데이트합니다.
- 패키지 변경 후에는 `requirements.txt`를 갱신하고 커밋에 포함하세요.
- `python3-venv` 패키지가 설치되어 있어야 합니다. (Debian/Ubuntu: `sudo apt install python3-venv`)

## 구조
```
reflector/
├── requirements.txt    # 고정된 의존성
├── src/
│   └── agent/
│       ├── __init__.py
│       ├── main.py          # 진입점
│       └── telemetry.py     # 메트릭 수집 유틸
└── README.md
```

## 수집 지표 & 기능 (v0.3)
- CPU 전체/코어별 사용률, load average, 클럭(MHz)
- 메모리 총량·사용량, 스왑 사용률
- 네트워크 인터페이스별 전송/수신 바이트, 패킷, 드롭/에러, 링크 속도(Mbps)
- 디스크 파티션별 총 용량과 사용량
- 센서 온도(`psutil.sensors_temperatures`)가 감지될 경우 최고 온도
- 상위 CPU 사용 프로세스 목록(top-K)
- `tags.primary_interface_speed_mbps` 등을 자동 설정하여 링크 용량을 백엔드에 전달, 필요 시 `config.json`의 `tags`로 덮어쓰기
- (선택) `command_endpoint`를 지정하면 명령 큐를 폴링하고 결과를 리포트

## 실행 (임시)
```bash
source .venv/bin/activate
PYTHONPATH=src python -m agent.main --once
```
단일 샘플을 수집해 JSON으로 출력합니다.

## 연속 업링크
- `config.json`에 백엔드 엔드포인트와 좌표/랙 정보를 정의.
- 링크 용량 계산을 위해 `tags.primary_interface_speed_mbps`(Mbps) 를 지정하거나, 에이전트가 자동 측정한 NIC 속도를 사용합니다.
- (선택) 원클릭 설치:
  ```bash
  curl -fsSLo install_reflector.sh https://raw.githubusercontent.com/DARC0625/MIRROR_STAGE/main/scripts/install_reflector.sh
  bash install_reflector.sh ~/mirror_stage_reflector
  ```
- 수동 실행 시 `start_reflector.sh` 스크립트로 백그라운드 실행:
  ```bash
  ./start_reflector.sh
  tail -f logs/reflector.log
  ```
- 중지:
  ```bash
  ./stop_reflector.sh
  ```

`config.json` 경로를 바꾸고 싶다면 `MIRROR_STAGE_REFLECTOR_CONFIG` 환경변수에 다른 파일 경로를 지정하세요.

### config.json 예시
```jsonc
{
  "endpoint": "http://10.0.0.100:3000/api/metrics/batch",
  "hostname_override": "rack-a-01",
  "rack": "Rack-A",
  "position": {"x": -3.2, "y": 1.0, "z": 4.4},
  "interval_seconds": 5,
  "tags": {"environment": "production"},
  "command_endpoint": "http://10.0.0.100:3000/api/commands",
  "command_poll_seconds": 15
}
```
