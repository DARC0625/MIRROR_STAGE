import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { AlertEntity, AlertSeverity } from './alert.entity';

/**
 * Metrics 평가를 위해 필요한 요약 값.
 */
interface SampleSummary {
  cpuLoad: number;
  memoryUsedPercent: number;
  gpuTemperature?: number | null;
  netThroughputGbps?: number | null;
  netCapacityGbps?: number | null;
}

/**
 * CPU/메모리/링크 상태 등을 기반으로 경보를 생성/해제하는 서비스.
 */
@Injectable()
export class AlertsService {
  constructor(
    @InjectRepository(AlertEntity)
    private readonly alertRepository: Repository<AlertEntity>,
  ) {}

  /**
   * Metric 샘플을 평가하여 여러 임계치 규칙을 동시에 처리한다.
   */
  async evaluateSample(hostname: string, summary: SampleSummary): Promise<void> {
    await Promise.all([
      this.handleThreshold(hostname, 'cpu_load_high', 'warning', 'CPU usage high', summary.cpuLoad, 80, 70),
      this.handleThreshold(hostname, 'memory_high', 'warning', 'Memory usage high', summary.memoryUsedPercent, 90, 80),
      this.handleThreshold(
        hostname,
        'gpu_temperature_high',
        'warning',
        'GPU temperature high',
        summary.gpuTemperature,
        80,
        70,
      ),
      this.handleThroughput(hostname, summary.netThroughputGbps, summary.netCapacityGbps),
    ]);
  }

  /** 현재 활성(alert) 상태인 항목만 조회한다. */
  async getActiveAlerts(): Promise<AlertEntity[]> {
    return this.alertRepository.find({
      where: { status: 'active' },
      order: { createdAt: 'DESC' },
    });
  }

  /** 특정 Alert 를 resolved 로 전환한다. */
  async resolveAlert(id: string): Promise<void> {
    const alert = await this.alertRepository.findOne({ where: { id } });
    if (!alert || alert.status === 'resolved') {
      return;
    }
    alert.status = 'resolved';
    alert.resolvedAt = new Date();
    await this.alertRepository.save(alert);
  }

  /**
   * 단일 임계치 기반 경고를 평가한다.
   * trigger 이상 → raise, clear 이하 → resolve, 그 사이 → 값만 갱신.
   */
  private async handleThreshold(
    hostname: string,
    metric: string,
    severity: AlertSeverity,
    message: string,
    value: number | undefined | null,
    trigger: number,
    clear: number,
  ): Promise<void> {
    if (value == null || !Number.isFinite(value)) {
      await this.resolveMetricAlert(hostname, metric);
      return;
    }

    if (value >= trigger) {
      await this.raiseAlert(hostname, metric, severity, message, trigger, value);
    } else if (value <= clear) {
      await this.resolveMetricAlert(hostname, metric);
    } else {
      await this.updateActiveAlert(hostname, metric, value);
    }
  }

  /** 링크 사용률 기반 혼잡 경고 평가. */
  private async handleThroughput(
    hostname: string,
    throughput: number | undefined | null,
    capacity: number | undefined | null,
  ): Promise<void> {
    if (!capacity || capacity <= 0 || throughput == null) {
      await this.resolveMetricAlert(hostname, 'link_congestion');
      return;
    }
    const utilization = throughput / capacity;
    if (utilization >= 0.9) {
      await this.raiseAlert(
        hostname,
        'link_congestion',
        utilization >= 1 ? 'critical' : 'warning',
        `Link utilization ${Math.round(utilization * 100)}%`,
        capacity,
        throughput,
      );
    } else if (utilization <= 0.7) {
      await this.resolveMetricAlert(hostname, 'link_congestion');
    } else {
      await this.updateActiveAlert(hostname, 'link_congestion', throughput);
    }
  }

  /** 새로운 경보를 만들거나, 이미 활성화된 항목의 값을 갱신한다. */
  private async raiseAlert(
    hostname: string,
    metric: string,
    severity: AlertSeverity,
    message: string,
    threshold: number | null,
    currentValue: number | null,
  ): Promise<void> {
    const existing = await this.alertRepository.findOne({ where: { hostname, metric, status: 'active' } });
    if (existing) {
      existing.currentValue = currentValue;
      existing.message = message;
      await this.alertRepository.save(existing);
      return;
    }

    const alert = this.alertRepository.create({
      hostname,
      metric,
      severity,
      message,
      threshold,
      currentValue,
      status: 'active',
    });
    await this.alertRepository.save(alert);
  }

  /** 해당 metric 의 활성 경보를 resolved 상태로 변경한다. */
  private async resolveMetricAlert(hostname: string, metric: string): Promise<void> {
    const existing = await this.alertRepository.findOne({ where: { hostname, metric, status: 'active' } });
    if (!existing) {
      return;
    }
    existing.status = 'resolved';
    existing.resolvedAt = new Date();
    await this.alertRepository.save(existing);
  }

  /** 경보는 유지하되 현재 값만 갱신한다. */
  private async updateActiveAlert(hostname: string, metric: string, currentValue: number): Promise<void> {
    const existing = await this.alertRepository.findOne({ where: { hostname, metric, status: 'active' } });
    if (!existing) {
      return;
    }
    existing.currentValue = currentValue;
    await this.alertRepository.save(existing);
  }
}
