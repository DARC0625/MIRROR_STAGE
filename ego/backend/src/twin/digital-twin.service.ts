import { randomUUID } from 'crypto';
import { Injectable, Logger } from '@nestjs/common';
import { BehaviorSubject } from 'rxjs';
import type { MetricSample } from '../metrics/metrics.dto';
import type { HostTwinState, TwinLink, TwinState, TwinPosition, HostMetricsSummary, TwinHostStatus } from './digital-twin.types';

interface HostState {
  hostname: string;
  displayName: string;
  ip: string;
  agentVersion: string;
  platform: string;
  rack?: string;
  metrics: HostMetricsSummary;
  lastSeen: number;
  positionOverride?: TwinPosition;
}

const GATEWAY_HOSTNAME = 'core-switch';
const GOLDEN_ANGLE = Math.PI * (3 - Math.sqrt(5));

@Injectable()
export class DigitalTwinService {
  private readonly logger = new Logger(DigitalTwinService.name);
  private readonly state = new Map<string, HostState>();
  private readonly ipAssignments = new Map<string, string>();
  private ipCursor = 10;
  private readonly twinSubject = new BehaviorSubject<TwinState>(this.buildSnapshot());
  private readonly twinId = `project5-${randomUUID().slice(0, 10)}`;

  readonly updates$ = this.twinSubject.asObservable();

  ingestSample(sample: MetricSample): void {
    const hostname = sample.hostname.trim();
    if (!hostname) {
      return;
    }

    const now = Date.now();
    const metrics: HostMetricsSummary = {
      cpuLoad: Number(sample.cpu_load ?? 0),
      memoryUsedPercent: Number(sample.memory_used_percent ?? 0),
      loadAverage: Number(sample.load_average ?? 0),
      uptimeSeconds: Number(sample.uptime_seconds ?? 0),
      gpuTemperature: sample.gpu_temperature ?? null,
      netBytesTx: sample.net_bytes_tx ?? null,
      netBytesRx: sample.net_bytes_rx ?? null,
    };

    const current: HostState = this.state.get(hostname) ?? {
      hostname,
      displayName: this.guessDisplayName(hostname),
      ip: this.ensureIp(hostname, sample.ip ?? sample.ipv4),
      agentVersion: sample.agent_version,
      platform: sample.platform,
      rack: sample.rack,
      metrics,
      lastSeen: now,
    };

    current.metrics = metrics;
    current.agentVersion = sample.agent_version;
    current.platform = sample.platform;
    current.rack = sample.rack ?? current.rack;
    current.lastSeen = now;
    current.positionOverride = sample.position
      ? {
          x: sample.position.x,
          y: sample.position.y,
          z: sample.position.z ?? 0,
        }
      : current.positionOverride;

    this.state.set(hostname, current);

    const snapshot = this.buildSnapshot();
    this.twinSubject.next(snapshot);
  }

  getSnapshot(): TwinState {
    return this.twinSubject.getValue();
  }

  private buildSnapshot(): TwinState {
    const now = Date.now();
    const hosts = Array.from(this.state.values()).sort((a, b) => a.hostname.localeCompare(b.hostname));

    const renderedHosts: HostTwinState[] = [];
    const links: TwinLink[] = [];

    const coreHost: HostTwinState = {
      hostname: GATEWAY_HOSTNAME,
      displayName: 'Core Switch',
      ip: '10.0.0.1',
      status: 'online',
      lastSeen: new Date(now).toISOString(),
      agentVersion: 'virtual',
      platform: 'virtual-switch',
      metrics: {
        cpuLoad: 12.5,
        memoryUsedPercent: 18.2,
        loadAverage: 0.8,
        uptimeSeconds: 86_400,
        gpuTemperature: null,
        netBytesTx: null,
        netBytesRx: null,
      },
      position: { x: 0, y: 0, z: 0 },
    };

    renderedHosts.push(coreHost);

    const total = hosts.length;
    hosts.forEach((host, index) => {
      const status = this.resolveStatus(now - host.lastSeen);
      const position =
        host.positionOverride ??
        this.computePosition(index, total, status === 'offline' ? 18 : 14);

      const twinHost: HostTwinState = {
        hostname: host.hostname,
        displayName: host.displayName,
        ip: host.ip,
        status,
        lastSeen: new Date(host.lastSeen).toISOString(),
        agentVersion: host.agentVersion,
        platform: host.platform,
        rack: host.rack,
        metrics: host.metrics,
        position,
      };

      renderedHosts.push(twinHost);

      const throughputGbps = this.estimateThroughput(host.metrics);
      const utilization = Math.min(1, host.metrics.cpuLoad / 100);

      links.push({
        id: `${coreHost.hostname}::${host.hostname}`,
        source: coreHost.hostname,
        target: host.hostname,
        throughputGbps: Number(throughputGbps.toFixed(3)),
        utilization: Number(utilization.toFixed(3)),
      });
    });

    return {
      type: 'twin-state',
      twinId: this.twinId,
      generatedAt: new Date(now).toISOString(),
      hosts: renderedHosts,
      links,
    };
  }

  private computePosition(index: number, total: number, radius = 14): TwinPosition {
    if (total <= 0) {
      return { x: 0, y: 0, z: 0 };
    }

    const angle = index * GOLDEN_ANGLE;
    const normalized = total > 1 ? index / (total - 1) : 0.5;
    const elevation = (normalized - 0.5) * radius * 0.25;
    const r = radius + Math.log(total + 1);

    return {
      x: Number((Math.cos(angle) * r).toFixed(3)),
      y: Number(elevation.toFixed(3)),
      z: Number((Math.sin(angle) * r).toFixed(3)),
    };
  }

  private resolveStatus(latency: number): TwinHostStatus {
    if (latency < 15_000) {
      return 'online';
    }
    if (latency < 60_000) {
      return 'stale';
    }
    return 'offline';
  }

  private estimateThroughput(metrics: HostMetricsSummary): number {
    const base = metrics.netBytesTx ?? metrics.netBytesRx ?? 0;
    if (base > 0) {
      return (base * 8) / 1_000_000_000;
    }
    return Math.max(0.05, (metrics.cpuLoad / 100) * 10);
  }

  private ensureIp(hostname: string, candidate?: string): string {
    if (candidate && this.isValidV4(candidate)) {
      this.ipAssignments.set(hostname, candidate);
      return candidate;
    }

    const existing = this.ipAssignments.get(hostname);
    if (existing) {
      return existing;
    }

    const ip = `10.0.0.${this.ipCursor++}`;
    this.ipAssignments.set(hostname, ip);
    return ip;
  }

  private isValidV4(candidate: string): boolean {
    const parts = candidate.split('.');
    if (parts.length !== 4) {
      return false;
    }
    return parts.every((part) => {
      const value = Number(part);
      return Number.isInteger(value) && value >= 0 && value <= 255;
    });
  }

  private guessDisplayName(hostname: string): string {
    if (!hostname.includes('-')) {
      return hostname.toUpperCase();
    }
    return hostname
      .split('-')
      .map((segment) => segment.charAt(0).toUpperCase() + segment.slice(1))
      .join(' ');
  }
}
