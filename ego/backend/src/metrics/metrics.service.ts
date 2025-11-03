import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { DigitalTwinService } from '../twin/digital-twin.service';
import type { MetricSample } from './metrics.dto';
import { HostMetricEntity } from '../persistence/host-metric.entity';
import { HostMetricSampleEntity } from '../persistence/host-metric-sample.entity';
import { AlertsService } from '../alerts/alerts.service';

@Injectable()
export class MetricsService {
  constructor(
    private readonly twinService: DigitalTwinService,
    private readonly alertsService: AlertsService,
    @InjectRepository(HostMetricEntity)
    private readonly hostMetricsRepository: Repository<HostMetricEntity>,
    @InjectRepository(HostMetricSampleEntity)
    private readonly metricSamplesRepository: Repository<HostMetricSampleEntity>,
  ) {}

  async ingestBatch(samples: MetricSample[]): Promise<number> {
    const entities: HostMetricEntity[] = [];
    const historyEntities: HostMetricSampleEntity[] = [];
    let processed = 0;

    for (const sample of samples) {
      const hostname = sample.hostname.trim();
      if (!hostname) {
        continue;
      }

      this.twinService.ingestSample(sample);
      const hostView = this.twinService.getHostTwinState(hostname);

      const tags = sample.tags ?? null;
      const position = sample.position;
      const parsedTimestamp = new Date(sample.timestamp);
      const lastSeen = Number.isNaN(parsedTimestamp.getTime()) ? new Date() : parsedTimestamp;
      const netBytesTx = sample.net_bytes_tx != null ? Number(sample.net_bytes_tx) : null;
      const netBytesRx = sample.net_bytes_rx != null ? Number(sample.net_bytes_rx) : null;
      const gpuTemperature = sample.gpu_temperature != null ? Number(sample.gpu_temperature) : null;
      const netCapacityGbps = this.extractCapacityGbps(sample);
      const netThroughputGbps = hostView?.metrics.netThroughputGbps ?? null;
      const resolvedCapacity = hostView?.metrics.netCapacityGbps ?? netCapacityGbps;

      await this.alertsService.evaluateSample(hostname, {
        cpuLoad: Number(sample.cpu_load ?? 0),
        memoryUsedPercent: Number(sample.memory_used_percent ?? 0),
        gpuTemperature,
        netThroughputGbps: netThroughputGbps ?? undefined,
        netCapacityGbps: resolvedCapacity ?? undefined,
      });

      const entity = this.hostMetricsRepository.create({
        hostname,
        displayName: hostname,
        ip: sample.ip ?? sample.ipv4 ?? null,
        rack: sample.rack ?? null,
        platform: sample.platform,
        agentVersion: sample.agent_version,
        cpuLoad: Number(sample.cpu_load ?? 0),
        memoryUsedPercent: Number(sample.memory_used_percent ?? 0),
        loadAverage: Number(sample.load_average ?? 0),
        uptimeSeconds: Number(sample.uptime_seconds ?? 0),
        gpuTemperature,
        netBytesTx,
        netBytesRx,
        netCapacityGbps: resolvedCapacity ?? null,
        netThroughputGbps,
        tags,
        positionX: position?.x ?? null,
        positionY: position?.y ?? null,
        positionZ: position?.z ?? null,
        lastSeen,
      });

      entities.push(entity);
      historyEntities.push(
        this.metricSamplesRepository.create({
          hostname,
          displayName: hostname,
          timestamp: lastSeen,
          cpuLoad: Number(sample.cpu_load ?? 0),
          memoryUsedPercent: Number(sample.memory_used_percent ?? 0),
          loadAverage: Number(sample.load_average ?? 0),
          uptimeSeconds: Number(sample.uptime_seconds ?? 0),
          gpuTemperature,
          netThroughputGbps,
          netCapacityGbps: resolvedCapacity ?? null,
          netBytesTx,
          netBytesRx,
          tags,
          position: position ?? null,
        }),
      );
      processed += 1;
    }

    if (entities.length > 0) {
      await this.hostMetricsRepository.save(entities);
    }
    if (historyEntities.length > 0) {
      await this.metricSamplesRepository.save(historyEntities);
    }

    return processed;
  }

  private extractCapacityGbps(sample: MetricSample): number | null {
    const tags = sample.tags ?? {};
    const candidate =
      tags?.primary_interface_speed_mbps ??
      tags?.interface_speed_mbps ??
      tags?.link_speed_mbps ??
      null;
    if (candidate) {
      const parsed = Number(candidate);
      if (Number.isFinite(parsed) && parsed > 0) {
        return parsed / 1_000;
      }
    }

    const raw = (sample as Record<string, unknown>).interfaces;
    if (Array.isArray(raw)) {
      let best = 0;
      for (const iface of raw) {
        if (!iface || typeof iface !== 'object') continue;
        const speed = Number((iface as Record<string, unknown>).speed_mbps);
        if (Number.isFinite(speed) && speed > best) {
          best = speed;
        }
      }
      if (best > 0) {
        return best / 1_000;
      }
    }
    return null;
  }
}
