/**
 * 디지털 트윈 영역에서 사용되는 타입 정의 모음.
 * Nest/Socket.IO 경계를 넘나들기 때문에 DTO 역할을 한다.
 */
export type TwinHostStatus = 'online' | 'stale' | 'offline';

export interface HostMetricsSummary {
  cpuLoad: number;
  memoryUsedPercent: number;
  loadAverage: number;
  uptimeSeconds: number;
  gpuTemperature?: number | null;
  cpuTemperature?: number | null;
  memoryTotalBytes?: number | null;
  memoryAvailableBytes?: number | null;
  netBytesTx?: number | null;
  netBytesRx?: number | null;
  netThroughputGbps?: number | null;
  netCapacityGbps?: number | null;
  swapUsedPercent?: number | null;
  cpuPerCore?: number[] | null;
}

export interface HostProcessSnapshot {
  pid: number;
  name: string;
  cpuPercent: number;
  memoryPercent?: number | null;
  username?: string | null;
}

export interface HostDiskSnapshot {
  device: string;
  mountpoint: string;
  totalBytes?: number | null;
  usedBytes?: number | null;
  usedPercent?: number | null;
}

export interface HostInterfaceSnapshot {
  name: string;
  speedMbps?: number | null;
  isUp?: boolean | null;
  bytesSent?: number | null;
  bytesRecv?: number | null;
}

export interface HostDiagnosticsSnapshot {
  cpuPerCore?: number[] | null;
  swapUsedPercent?: number | null;
  topProcesses?: HostProcessSnapshot[];
  disks?: HostDiskSnapshot[];
  interfaces?: HostInterfaceSnapshot[];
  tags?: Record<string, string>;
}

export interface HostHardwareSummary {
  systemManufacturer?: string | null;
  systemModel?: string | null;
  biosVersion?: string | null;
  cpuModel?: string | null;
  cpuPhysicalCores?: number | null;
  cpuLogicalCores?: number | null;
  memoryTotalBytes?: number | null;
  osDistro?: string | null;
  osRelease?: string | null;
  osKernel?: string | null;
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
  hardware?: HostHardwareSummary;
  diagnostics?: HostDiagnosticsSnapshot;
  isSynthetic?: boolean;
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
