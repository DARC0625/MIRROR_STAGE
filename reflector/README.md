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

## 실행 (임시)
```bash
source .venv/bin/activate
PYTHONPATH=src python -m agent.main --once
```
현재는 단일 샘플 메트릭을 출력하는 플레이스홀더이며, 추후 MQTT/HTTPS 업링크 및 명령 실행 루프가 추가됩니다.

## 연속 업링크
- `config.json`에 백엔드 엔드포인트와 좌표/랙 정보를 정의.
- `start_reflector.sh` 스크립트로 백그라운드 실행:
  ```bash
  ./start_reflector.sh
  tail -f logs/reflector.log
  ```
- 중지:
  ```bash
  ./stop_reflector.sh
  ```

`config.json` 경로를 바꾸고 싶다면 `MIRROR_STAGE_REFLECTOR_CONFIG` 환경변수에 다른 파일 경로를 지정하세요.
