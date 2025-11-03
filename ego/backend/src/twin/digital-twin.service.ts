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
  previousNetBytesTx?: number | null;
  previousNetBytesRx?: number | null;
  previousSampleTimestamp?: number | null;
  netCapacityGbps?: number | null;
}

const EGO_HOSTNAME = process.env.EGO_HOSTNAME ?? 'ego-hub';
const EGO_DISPLAY_NAME = process.env.EGO_DISPLAY_NAME ?? 'MIRROR STAGE EGO';
const EGO_PRIMARY_IP = process.env.EGO_PRIMARY_IP ?? '10.0.0.100';
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
    const sampleTimestamp = this.parseTimestamp(sample.timestamp, now);
    const metrics: HostMetricsSummary = {
      cpuLoad: Number(sample.cpu_load ?? 0),
      memoryUsedPercent: Number(sample.memory_used_percent ?? 0),
      loadAverage: Number(sample.load_average ?? 0),
      uptimeSeconds: Number(sample.uptime_seconds ?? 0),
      gpuTemperature: sample.gpu_temperature ?? null,
      netBytesTx: sample.net_bytes_tx ?? null,
      netBytesRx: sample.net_bytes_rx ?? null,
      netThroughputGbps: null,
      netCapacityGbps: null,
    };

    const ipAddress = this.ensureIp(hostname, sample.ip ?? sample.ipv4);

    const current: HostState = this.state.get(hostname) ?? {
      hostname,
      displayName: hostname,
      ip: ipAddress,
      agentVersion: sample.agent_version,
      platform: sample.platform,
      rack: sample.rack,
      metrics,
      lastSeen: now,
      previousNetBytesTx: sample.net_bytes_tx ?? null,
      previousNetBytesRx: sample.net_bytes_rx ?? null,
      previousSampleTimestamp: sampleTimestamp,
      netCapacityGbps: null,
    };

    const capacityGbps = this.extractCapacityGbps(sample, current.netCapacityGbps);
    const throughputGbps = this.computeThroughputGbps(current, sample, sampleTimestamp);

    metrics.netThroughputGbps = throughputGbps ?? current.metrics.netThroughputGbps ?? null;
    metrics.netCapacityGbps = capacityGbps ?? metrics.netCapacityGbps ?? null;

    current.ip = ipAddress;
    current.metrics = metrics;
    current.agentVersion = sample.agent_version;
    current.platform = sample.platform;
    current.rack = sample.rack ?? current.rack;
    current.lastSeen = now;
    current.netCapacityGbps = metrics.netCapacityGbps ?? null;
    current.previousNetBytesTx = sample.net_bytes_tx ?? current.previousNetBytesTx ?? null;
    current.previousNetBytesRx = sample.net_bytes_rx ?? current.previousNetBytesRx ?? null;
    current.previousSampleTimestamp = sampleTimestamp;
    current.positionOverride = sample.position
      ? {
          x: sample.position.x,
          y: sample.position.y,
          z: sample.position.z ?? 0,
        }
      : current.positionOverride;
    current.displayName = this.formatReflectorName(current);

    this.state.set(hostname, current);

    const snapshot = this.buildSnapshot();
    this.twinSubject.next(snapshot);
  }

  getSnapshot(): TwinState {
    return this.twinSubject.getValue();
  }


  private buildSnapshot(): TwinState {
    const now = Date.now();
    const allHosts = Array.from(this.state.values());
    const egoIndex = allHosts.findIndex((host) => this.isEgoHost(host));
    const egoState = egoIndex >= 0 ? allHosts.splice(egoIndex, 1)[0] : undefined;

    const hosts = allHosts.sort((a, b) => a.hostname.localeCompare(b.hostname));

    const renderedHosts: HostTwinState[] = [];
    const links: TwinLink[] = [];

    const egoHost = this.buildEgoHost(egoState, now);
    renderedHosts.push(egoHost);

    const total = hosts.length;
    hosts.forEach((host, index) => {
      const status = this.resolveStatus(now - host.lastSeen);
      host.displayName = this.formatReflectorName(host);
      const position =
        host.positionOverride ??
        this.computePosition(index, total, status === 'offline' ? 18 : 14);

      const label = this.formatLabel(host.displayName, host.ip, host.rack);

      const twinHost: HostTwinState = {
        hostname: host.hostname,
        displayName: host.displayName,
        label,
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
      const capacityGbps = host.metrics.netCapacityGbps ?? host.netCapacityGbps ?? null;
      let utilization: number;
      if (capacityGbps && capacityGbps > 0) {
        utilization = Math.min(1, throughputGbps / capacityGbps);
      } else {
        utilization = Math.min(1, Math.max(host.metrics.cpuLoad / 100, throughputGbps / 10));
      }

      links.push({
        id: `${egoHost.hostname}::${host.hostname}`,
        source: egoHost.hostname,
        target: host.hostname,
        throughputGbps: Number(throughputGbps.toFixed(3)),
        utilization: Number(utilization.toFixed(3)),
        capacityGbps: capacityGbps ? Number(capacityGbps.toFixed(3)) : null,
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
    if (metrics.netThroughputGbps != null) {
      return Math.max(0, metrics.netThroughputGbps);
    }

    const base = metrics.netBytesTx ?? metrics.netBytesRx ?? 0;
    if (base > 0) {
      return Math.max(0.01, (base * 8) / 1_000_000_000);
    }
    return Math.max(0.05, (metrics.cpuLoad / 100) * 2);
  }

  private parseTimestamp(timestamp: string | undefined, fallbackMs: number): number {
    if (timestamp) {
      const parsed = Date.parse(timestamp);
      if (!Number.isNaN(parsed)) {
        return parsed;
      }
    }
    return fallbackMs;
  }

  private extractCapacityGbps(sample: MetricSample, fallback?: number | null): number | null {
    const tags = sample.tags ?? {};
    const tagCandidate =
      tags?.primary_interface_speed_mbps ??
      tags?.interface_speed_mbps ??
      tags?.link_speed_mbps ??
      null;

    let capacity = fallback ?? null;

    if (tagCandidate) {
      const parsedTag = Number(tagCandidate);
      if (Number.isFinite(parsedTag) && parsedTag > 0) {
        capacity = parsedTag / 1_000;
      }
    }

    if (!capacity) {
      const fromInterfaces = this.extractCapacityFromInterfaces(sample);
      if (fromInterfaces) {
        capacity = fromInterfaces;
      }
    }

    return capacity;
  }

  private extractCapacityFromInterfaces(sample: MetricSample): number | null {
    const raw = (sample as Record<string, unknown>).interfaces;
    if (!Array.isArray(raw)) {
      return null;
    }

    let bestSpeedMbps = 0;
    for (const entry of raw) {
      if (!entry || typeof entry !== 'object') continue;
      const speedCandidate = Number((entry as Record<string, unknown>).speed_mbps);
      const isUp = (entry as Record<string, unknown>).is_up;
      if (Number.isFinite(speedCandidate) && speedCandidate > bestSpeedMbps && (isUp === true || isUp === undefined)) {
        bestSpeedMbps = speedCandidate;
      }
    }

    if (bestSpeedMbps > 0) {
      return bestSpeedMbps / 1_000;
    }
    return null;
  }

  private computeThroughputGbps(state: HostState, sample: MetricSample, sampleTimestamp: number): number | null {
    const prevTimestamp = state.previousSampleTimestamp;
    const txNow = sample.net_bytes_tx ?? null;
    const rxNow = sample.net_bytes_rx ?? null;

    if (txNow == null && rxNow == null) {
      return null;
    }

    if (prevTimestamp && sampleTimestamp > prevTimestamp) {
      const deltaSeconds = (sampleTimestamp - prevTimestamp) / 1000;
      if (deltaSeconds <= 0) {
        return null;
      }

      const previousTx = state.previousNetBytesTx ?? txNow ?? 0;
      const previousRx = state.previousNetBytesRx ?? rxNow ?? 0;

      let deltaTx = txNow != null ? txNow - previousTx : 0;
      let deltaRx = rxNow != null ? rxNow - previousRx : 0;

      if (!Number.isFinite(deltaTx)) deltaTx = 0;
      if (!Number.isFinite(deltaRx)) deltaRx = 0;
      if (deltaTx < 0) deltaTx = 0;
      if (deltaRx < 0) deltaRx = 0;

      const totalDeltaBytes = deltaTx + deltaRx;
      if (totalDeltaBytes <= 0) {
        return 0;
      }

      const bitsPerSecond = (totalDeltaBytes * 8) / deltaSeconds;
      const gbps = bitsPerSecond / 1_000_000_000;
      if (Number.isFinite(gbps)) {
        return Number(gbps.toFixed(4));
      }
    }

    return null;
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


  private formatReflectorName(host: HostState): string {
    const ip = host.ip;
    if (ip && this.isValidV4(ip)) {
      const octet = ip.split('.').pop() ?? 'X';
      return `REFLECTOR-${octet.padStart(3, '0')}`;
    }

    const normalized = host.hostname.trim();
    if (!normalized) {
      return 'REFLECTOR-UNKNOWN';
    }

    return `REFLECTOR-${normalized.replace(/[^a-zA-Z0-9]/g, '-').toUpperCase()}`;
  }

  private formatLabel(displayName: string, ip: string, rack?: string): string {
    const segments = [displayName, ip];
    if (rack) {
      segments.push(rack);
    }
    return segments.join('\n');
  }

  private buildEgoHost(egoState: HostState | undefined, timestamp: number): HostTwinState {
    const metrics = egoState?.metrics ?? this.defaultCoreMetrics();
    if (metrics.netThroughputGbps == null) {
      metrics.netThroughputGbps = egoState?.metrics?.netThroughputGbps ?? 0;
    }
    if (metrics.netCapacityGbps == null) {
      metrics.netCapacityGbps = egoState?.netCapacityGbps ?? null;
    }
    const ip = egoState?.ip ?? EGO_PRIMARY_IP;
    const lastSeenTimestamp = egoState?.lastSeen ?? timestamp;
    const status = egoState ? this.resolveStatus(timestamp - egoState.lastSeen) : 'online';

    return {
      hostname: EGO_HOSTNAME,
      displayName: EGO_DISPLAY_NAME,
      label: this.formatLabel(EGO_DISPLAY_NAME, ip, egoState?.rack),
      ip,
      status,
      lastSeen: new Date(lastSeenTimestamp).toISOString(),
      agentVersion: egoState?.agentVersion ?? 'ego',
      platform: egoState?.platform ?? 'ego-backend',
      rack: egoState?.rack,
      metrics,
      position: { x: 0, y: 0, z: 0 },
    };
  }

  private isEgoHost(host: HostState): boolean {
    if (!host) {
      return false;
    }
    if (host.ip && this.isValidV4(host.ip) && host.ip === EGO_PRIMARY_IP) {
      return true;
    }
    const normalized = host.hostname.toLowerCase();
    return normalized === EGO_HOSTNAME || normalized === EGO_DISPLAY_NAME.toLowerCase();
  }

  private defaultCoreMetrics(): HostMetricsSummary {
    return {
      cpuLoad: 0,
      memoryUsedPercent: 0,
      loadAverage: 0,
      uptimeSeconds: 0,
      gpuTemperature: null,
      netBytesTx: null,
      netBytesRx: null,
      netThroughputGbps: null,
      netCapacityGbps: null,
    };
  }
}
