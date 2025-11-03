import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { AlertEntity, AlertSeverity } from './alert.entity';

interface SampleSummary {
  cpuLoad: number;
  memoryUsedPercent: number;
  gpuTemperature?: number | null;
  netThroughputGbps?: number | null;
  netCapacityGbps?: number | null;
}

@Injectable()
export class AlertsService {
  constructor(
    @InjectRepository(AlertEntity)
    private readonly alertRepository: Repository<AlertEntity>,
  ) {}

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

  async getActiveAlerts(): Promise<AlertEntity[]> {
    return this.alertRepository.find({
      where: { status: 'active' },
      order: { createdAt: 'DESC' },
    });
  }

  async resolveAlert(id: string): Promise<void> {
    const alert = await this.alertRepository.findOne({ where: { id } });
    if (!alert || alert.status === 'resolved') {
      return;
    }
    alert.status = 'resolved';
    alert.resolvedAt = new Date();
    await this.alertRepository.save(alert);
  }

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

  private async resolveMetricAlert(hostname: string, metric: string): Promise<void> {
    const existing = await this.alertRepository.findOne({ where: { hostname, metric, status: 'active' } });
    if (!existing) {
      return;
    }
    existing.status = 'resolved';
    existing.resolvedAt = new Date();
    await this.alertRepository.save(existing);
  }

  private async updateActiveAlert(hostname: string, metric: string, currentValue: number): Promise<void> {
    const existing = await this.alertRepository.findOne({ where: { hostname, metric, status: 'active' } });
    if (!existing) {
      return;
    }
    existing.currentValue = currentValue;
    await this.alertRepository.save(existing);
  }
}
