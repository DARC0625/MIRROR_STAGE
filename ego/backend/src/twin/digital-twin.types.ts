export type TwinHostStatus = 'online' | 'stale' | 'offline';

export interface HostMetricsSummary {
  cpuLoad: number;
  memoryUsedPercent: number;
  loadAverage: number;
  uptimeSeconds: number;
  gpuTemperature?: number | null;
  netBytesTx?: number | null;
  netBytesRx?: number | null;
  netThroughputGbps?: number | null;
  netCapacityGbps?: number | null;
}

export interface TwinPosition {
  x: number;
  y: number;
  z: number;
}

export interface HostTwinState {
  hostname: string;
  displayName: string;
  ip: string;
  label?: string;
  status: TwinHostStatus;
  lastSeen: string;
  agentVersion: string;
  platform: string;
  rack?: string;
  metrics: HostMetricsSummary;
  position: TwinPosition;
}

export interface TwinLink {
  id: string;
  source: string;
  target: string;
  throughputGbps: number;
  utilization: number;
  capacityGbps?: number | null;
}

export interface TwinState {
  type: 'twin-state';
  twinId: string;
  generatedAt: string;
  hosts: HostTwinState[];
  links: TwinLink[];
}
