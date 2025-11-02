# API Contracts (Draft)

This document will hold the OpenAPI/Protobuf definitions once the stack is confirmed.

## REST

### `POST /api/metrics/batch`

```jsonc
{
  "samples": [
    {
      "hostname": "titan-01",
      "timestamp": "2025-11-01T02:15:00.000Z",
      "cpu_load": 42.5,
      "memory_used_percent": 63.2,
      "load_average": 1.72,
      "uptime_seconds": 7200,
      "agent_version": "0.1.0-dev",
      "platform": "Linux-x86_64",
      "net_bytes_tx": 1250000000,
      "net_bytes_rx": 980000000,
      "rack": "R1",
      "position": { "x": 1.2, "y": 0.4, "z": -0.8 }
    }
  ]
}
```

Response `202 Accepted`

```json
{
  "accepted": 1,
  "receivedAt": "2025-11-01T02:15:00.123Z"
}
```

### `GET /api/twin/state`

Returns the current in-memory digital twin snapshot.

```jsonc
{
  "type": "twin-state",
  "twinId": "project5-a1b2c3d4",
  "generatedAt": "2025-11-01T02:15:01.005Z",
  "hosts": [
    {
      "hostname": "core-switch",
      "displayName": "Core Switch",
      "ip": "10.0.0.1",
      "status": "online",
      "lastSeen": "2025-11-01T02:15:01.005Z",
      "agentVersion": "virtual",
      "platform": "virtual-switch",
      "metrics": {
        "cpuLoad": 12.5,
        "memoryUsedPercent": 18.2,
        "loadAverage": 0.8,
        "uptimeSeconds": 86400
      },
      "position": { "x": 0, "y": 0, "z": 0 }
    },
    {
      "hostname": "titan-01",
      "displayName": "Titan 01",
      "ip": "10.0.0.10",
      "status": "online",
      "lastSeen": "2025-11-01T02:15:00.950Z",
      "agentVersion": "0.1.0-dev",
      "platform": "Linux-x86_64",
      "rack": "R1",
      "metrics": {
        "cpuLoad": 42.5,
        "memoryUsedPercent": 63.2,
        "loadAverage": 1.72,
        "uptimeSeconds": 7200,
        "netBytesTx": 1250000000,
        "netBytesRx": 980000000
      },
      "position": { "x": 13.2, "y": 1.1, "z": -4.5 }
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

## Socket.IO

- Namespace: `/digital-twin`
- Event: `twin-state` (payload 동일)

## Pending Tasks
- Define `HostRegistrationRequest` and response payload.
- Model `MetricsBatch` schema including sequence numbers and signatures.
- Outline WebSocket event envelopes for live dashboard updates.
- Specify command lifecycle endpoints (`/commands`, `/commands/{id}/result`).

Use this file to track schema revisions before they are codified into the backend service.
