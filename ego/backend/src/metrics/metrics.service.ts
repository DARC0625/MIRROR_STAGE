import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { DigitalTwinService } from '../twin/digital-twin.service';
import type { MetricSample } from './metrics.dto';
import { HostMetricEntity } from '../persistence/host-metric.entity';

@Injectable()
export class MetricsService {
  constructor(
    private readonly twinService: DigitalTwinService,
    @InjectRepository(HostMetricEntity)
    private readonly hostMetricsRepository: Repository<HostMetricEntity>,
  ) {}

  async ingestBatch(samples: MetricSample[]): Promise<number> {
    const entities: HostMetricEntity[] = [];
    let processed = 0;

    for (const sample of samples) {
      const hostname = sample.hostname.trim();
      if (!hostname) {
        continue;
      }

      this.twinService.ingestSample(sample);

      const tags = sample.tags ?? null;
      const position = sample.position;
      const parsedTimestamp = new Date(sample.timestamp);
      const lastSeen = Number.isNaN(parsedTimestamp.getTime()) ? new Date() : parsedTimestamp;
      const netBytesTx = sample.net_bytes_tx != null ? Number(sample.net_bytes_tx) : null;
      const netBytesRx = sample.net_bytes_rx != null ? Number(sample.net_bytes_rx) : null;
      const gpuTemperature = sample.gpu_temperature != null ? Number(sample.gpu_temperature) : null;
      const netCapacityGbps = this.extractCapacityGbps(sample);

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
        netCapacityGbps,
        netThroughputGbps: null,
        tags,
        positionX: position?.x ?? null,
        positionY: position?.y ?? null,
        positionZ: position?.z ?? null,
        lastSeen,
      });

      entities.push(entity);
      processed += 1;
    }

    if (entities.length > 0) {
      await this.hostMetricsRepository.save(entities);
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
