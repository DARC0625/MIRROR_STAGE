import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SchedulerRegistry } from '@nestjs/schedule';
import { MetricsService } from '../metrics/metrics.service';
import type { MetricSample } from '../metrics/metrics.dto';
import * as os from 'os';
import si from 'systeminformation';
import type { Systeminformation } from 'systeminformation';

interface PrimaryInterface {
  iface: string;
  ip4?: string;
  speed?: number;
}

interface HardwareSnapshot {
  systemManufacturer?: string;
  systemModel?: string;
  biosVersion?: string;
  cpuModel?: string;
  cpuPhysicalCores?: number;
  cpuLogicalCores?: number;
  memoryTotalBytes?: number;
  osDistro?: string;
  osRelease?: string;
  osKernel?: string;
}

@Injectable()
export class EgoMonitorService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(EgoMonitorService.name);
  private readonly enabled: boolean;
  private readonly intervalMs: number;
  private readonly hostnameOverride?: string;
  private readonly rack?: string;
  private readonly displayNameOverride?: string;
  private hardwareSnapshotPromise: Promise<HardwareSnapshot> | null = null;

  constructor(
    private readonly configService: ConfigService,
    private readonly metricsService: MetricsService,
    private readonly schedulerRegistry: SchedulerRegistry,
  ) {
    const isTestEnvironment =
      this.configService.get<string>('NODE_ENV') === 'test' || process.env.JEST_WORKER_ID !== undefined;
    const enabledFlag = this.configService.get<string>('MIRROR_STAGE_EGO_MONITOR_ENABLED', 'true') !== 'false';
    this.enabled = !isTestEnvironment && enabledFlag;
    const requestedInterval = Number(this.configService.get<string>('MIRROR_STAGE_EGO_MONITOR_INTERVAL_MS') ?? '1000');
    this.intervalMs = Number.isFinite(requestedInterval) && requestedInterval >= 500 ? requestedInterval : 1000;
    this.hostnameOverride = this.configService.get<string>('EGO_HOSTNAME');
    this.displayNameOverride = this.configService.get<string>('EGO_DISPLAY_NAME');
    this.rack = this.configService.get<string>('EGO_RACK');
  }

  onModuleInit(): void {
    if (!this.enabled) {
      const isTestEnvironment = this.configService.get<string>('NODE_ENV') === 'test' || process.env.JEST_WORKER_ID !== undefined;
      if (isTestEnvironment) {
        this.logger.debug('EGO monitor skipped in test environment');
      } else {
        this.logger.warn('EGO monitor disabled (MIRROR_STAGE_EGO_MONITOR_ENABLED=false)');
      }
      return;
    }

    this.logger.log(`EGO monitor enabled (interval ${this.intervalMs} ms)`);
    const interval = setInterval(() => {
      this.collectAndPublish()
        .then(() => {
          // noop
        })
        .catch((error) => {
          this.logger.error('Failed to publish EGO metrics', error);
        });
    }, this.intervalMs);

    this.schedulerRegistry.addInterval('ego-monitor', interval);
    // fire immediately once
    this.collectAndPublish().catch((error) => this.logger.error('Initial EGO metrics collection failed', error));
  }

  onModuleDestroy(): void {
    if (!this.enabled) {
      return;
    }
    try {
      this.schedulerRegistry.deleteInterval('ego-monitor');
    } catch (error) {
      if (error instanceof Error && error.message.includes('ego-monitor')) {
        return;
      }
      this.logger.error('Failed to dispose ego monitor interval', error as Error);
    }
  }

  private async collectAndPublish(): Promise<void> {
    const hostname = (this.hostnameOverride ?? os.hostname()).trim() || 'ego-hub';
    const timestamp = new Date().toISOString();

    const [load, memory, osInfo, timeInfo, cpuTemperatureInfo, graphicsInfo, hardwareInfo] = await Promise.all([
      this.safeCollect(() => si.currentLoad(), 'currentLoad'),
      this.safeCollect(() => si.mem(), 'mem'),
      this.safeCollect(() => si.osInfo(), 'osInfo'),
      this.safeCollect(() => si.time(), 'time'),
      this.safeCollect(() => si.cpuTemperature(), 'cpuTemperature'),
      this.safeCollect(() => si.graphics(), 'graphics'),
      this.resolveHardwareSnapshot(),
    ]);

    const primaryInterface = await this.resolvePrimaryInterface();
    let netBytesTx: number | null = null;
    let netBytesRx: number | null = null;
    if (primaryInterface) {
      try {
        const stats = await si.networkStats(primaryInterface.iface);
        if (stats?.length) {
          const stat = stats[0];
          netBytesTx = Number.isFinite(stat?.tx_bytes) ? Math.max(0, Math.trunc(stat.tx_bytes)) : null;
          netBytesRx = Number.isFinite(stat?.rx_bytes) ? Math.max(0, Math.trunc(stat.rx_bytes)) : null;
        }
      } catch (error) {
        this.logger.warn(`systeminformation.networkStats failed: ${error}`);
      }
    }

    const currentLoadValue = typeof load?.currentLoad === 'number' ? load.currentLoad : 0;
    const cpuLoad = Number(currentLoadValue.toFixed(2));

    const activeMemoryCandidate =
      typeof memory?.active === 'number'
        ? memory.active
        : typeof memory?.used === 'number'
        ? memory.used
        : 0;
    const totalMemory = typeof memory?.total === 'number' ? memory.total : 0;
    const memoryPercent =
      totalMemory > 0 ? Number(((activeMemoryCandidate / totalMemory) * 100).toFixed(2)) : 0;

    const loadRecord = load as unknown as Record<string, unknown> | null;
    const avgLoadFromStruct =
      typeof load?.avgLoad === 'number'
        ? load.avgLoad
        : loadRecord != null && typeof loadRecord['avgload'] === 'number'
        ? Number(loadRecord['avgload'])
        : null;
    const loadAverageSource = avgLoadFromStruct ?? os.loadavg()[0] ?? 0;
    const loadAverage = Number(loadAverageSource.toFixed(2));

    const uptimeValueRaw = timeInfo?.uptime;
    const uptimeValue = Number(uptimeValueRaw ?? process.uptime());
    const uptimeSeconds = Number.isFinite(uptimeValue) ? Math.max(Math.floor(uptimeValue), 0) : Math.floor(process.uptime());
    const tags: Record<string, string> = {
      source: 'ego-monitor',
    };
    const cpuTemperature = this.extractCpuTemperature(cpuTemperatureInfo);
    const gpuTemperature = this.extractGpuTemperature(graphicsInfo);

    if (primaryInterface?.iface) {
      tags.primary_interface = primaryInterface.iface;
    }
    if (primaryInterface?.speed) {
      tags.primary_interface_speed_mbps = String(primaryInterface.speed);
    }
    if (hardwareInfo.systemManufacturer) {
      tags.system_manufacturer = hardwareInfo.systemManufacturer;
    }
    if (hardwareInfo.systemModel) {
      tags.system_model = hardwareInfo.systemModel;
    }
    if (hardwareInfo.cpuModel) {
      tags.cpu_model = hardwareInfo.cpuModel;
    }
    if (hardwareInfo.cpuPhysicalCores) {
      tags.cpu_physical_cores = String(hardwareInfo.cpuPhysicalCores);
    }
    if (hardwareInfo.cpuLogicalCores) {
      tags.cpu_logical_cores = String(hardwareInfo.cpuLogicalCores);
    }
    if (hardwareInfo.memoryTotalBytes) {
      tags.memory_total_bytes = String(hardwareInfo.memoryTotalBytes);
    }
    if (hardwareInfo.osDistro) {
      tags.os_distro = hardwareInfo.osDistro;
    }
    if (hardwareInfo.osRelease) {
      tags.os_release = hardwareInfo.osRelease;
    }
    if (hardwareInfo.osKernel) {
      tags.os_kernel = hardwareInfo.osKernel;
    }

    const sample: MetricSample = {
      hostname,
      timestamp,
      cpu_load: cpuLoad,
      memory_used_percent: Math.min(Math.max(memoryPercent, 0), 100),
      load_average: loadAverage,
      uptime_seconds: Math.max(uptimeSeconds, 0),
      agent_version: `ego-monitor/${process.env.npm_package_version ?? 'dev'}`,
      platform: `${osInfo?.distro ?? os.type()} ${osInfo?.release ?? ''}`.trim(),
      gpu_temperature: gpuTemperature ?? undefined,
      cpu_temperature: cpuTemperature ?? undefined,
      memory_total_bytes:
        hardwareInfo.memoryTotalBytes ?? (typeof memory?.total === 'number' ? Math.max(Math.trunc(memory.total), 0) : undefined),
      memory_available_bytes:
        typeof memory?.available === 'number' ? Math.max(Math.trunc(memory.available), 0) : undefined,
      system_manufacturer: hardwareInfo.systemManufacturer,
      system_model: hardwareInfo.systemModel,
      bios_version: hardwareInfo.biosVersion,
      cpu_model: hardwareInfo.cpuModel,
      cpu_physical_cores: hardwareInfo.cpuPhysicalCores,
      cpu_logical_cores: hardwareInfo.cpuLogicalCores,
      os_distro: hardwareInfo.osDistro ?? osInfo?.distro,
      os_release: hardwareInfo.osRelease ?? osInfo?.release,
      os_kernel: hardwareInfo.osKernel ?? osInfo?.kernel,
      primary_interface_speed_mbps: primaryInterface?.speed,
      net_bytes_tx: netBytesTx ?? undefined,
      net_bytes_rx: netBytesRx ?? undefined,
      ip: primaryInterface?.ip4 ?? this.resolveFallbackIp(),
      rack: this.rack ?? undefined,
      position: undefined,
      tags,
    };

    await this.metricsService.ingestBatch([sample]);
  }

  private extractCpuTemperature(
    cpuTemperatureInfo: Awaited<ReturnType<typeof si.cpuTemperature>> | null,
  ): number | null {
    if (!cpuTemperatureInfo) {
      return null;
    }
    const main = (cpuTemperatureInfo as { main?: number }).main;
    if (typeof main === 'number' && Number.isFinite(main)) {
      return Number(main.toFixed(1));
    }
    const cores = (cpuTemperatureInfo as { cores?: number[] }).cores;
    if (Array.isArray(cores) && cores.length > 0) {
      const valid = cores.filter((value) => typeof value === 'number' && Number.isFinite(value));
      if (valid.length > 0) {
        const sum = valid.reduce((acc, value) => acc + value, 0);
        return Number((sum / valid.length).toFixed(1));
      }
    }
    return null;
  }

  private extractGpuTemperature(
    graphicsInfo: Awaited<ReturnType<typeof si.graphics>> | null,
  ): number | null {
    if (!graphicsInfo) {
      return null;
    }
    const controllers = (graphicsInfo as Systeminformation.GraphicsData).controllers ?? [];
    if (!Array.isArray(controllers) || controllers.length === 0) {
      return null;
    }
    const temperatures = controllers
      .map((controller) => controller?.temperatureGpu)
      .filter((value): value is number => typeof value === 'number' && Number.isFinite(value));
    if (temperatures.length === 0) {
      return null;
    }
    return Number(Math.max(...temperatures).toFixed(1));
  }

  private async resolveHardwareSnapshot(): Promise<HardwareSnapshot> {
    if (!this.hardwareSnapshotPromise) {
      this.hardwareSnapshotPromise = this.fetchHardwareSnapshot();
    }
    try {
      return await this.hardwareSnapshotPromise;
    } catch (error) {
      this.logger.warn(`Failed to resolve hardware snapshot: ${error}`);
      this.hardwareSnapshotPromise = null;
      return {};
    }
  }

  private async fetchHardwareSnapshot(): Promise<HardwareSnapshot> {
    const [systemInfo, biosInfo, cpuInfo, memInfo, osInfo] = await Promise.all([
      this.safeCollect(() => si.system(), 'system'),
      this.safeCollect(() => si.bios(), 'bios'),
      this.safeCollect(() => si.cpu(), 'cpu'),
      this.safeCollect(() => si.mem(), 'mem'),
      this.safeCollect(() => si.osInfo(), 'osInfo'),
    ]);

    return {
      systemManufacturer: typeof systemInfo?.manufacturer === 'string' ? systemInfo.manufacturer : undefined,
      systemModel: typeof systemInfo?.model === 'string' ? systemInfo.model : undefined,
      biosVersion: typeof biosInfo?.version === 'string' ? biosInfo.version : undefined,
      cpuModel: typeof cpuInfo?.brand === 'string' && cpuInfo.brand.trim().length > 0 ? cpuInfo.brand : cpuInfo?.model,
      cpuPhysicalCores: typeof cpuInfo?.physicalCores === 'number' ? cpuInfo.physicalCores : undefined,
      cpuLogicalCores: typeof cpuInfo?.cores === 'number' ? cpuInfo.cores : undefined,
      memoryTotalBytes: typeof memInfo?.total === 'number' ? Math.max(Math.trunc(memInfo.total), 0) : undefined,
      osDistro: typeof osInfo?.distro === 'string' ? osInfo.distro : undefined,
      osRelease: typeof osInfo?.release === 'string' ? osInfo.release : undefined,
      osKernel: typeof osInfo?.kernel === 'string' ? osInfo.kernel : undefined,
    };
  }

  private async resolvePrimaryInterface(): Promise<PrimaryInterface | null> {
    try {
      const interfaces = await si.networkInterfaces();
      const candidate =
        interfaces.find((item) => item.default || item.virtual === false) ??
        interfaces.find((item) => item.ip4 && !item.internal) ??
        null;
      if (!candidate) {
        return null;
      }
      return {
        iface: candidate.iface,
        ip4: candidate.ip4 || undefined,
        speed: candidate.speed && candidate.speed > 0 ? candidate.speed : undefined,
      };
    } catch (error) {
      this.logger.warn(`systeminformation.networkInterfaces failed: ${error}`);
      return null;
    }
  }

  private async safeCollect<T>(fn: () => Promise<T> | T, label: string): Promise<T | null> {
    try {
      return await Promise.resolve(fn());
    } catch (error) {
      this.logger.warn(`systeminformation.${label} failed: ${error}`);
      return null;
    }
  }

  private resolveFallbackIp(): string | undefined {
    const networks = os.networkInterfaces();
    for (const iface of Object.values(networks)) {
      if (!iface) continue;
      for (const address of iface) {
        if (address.family === 'IPv4' && !address.internal && address.address) {
          return address.address;
        }
      }
    }
    return undefined;
  }
}
