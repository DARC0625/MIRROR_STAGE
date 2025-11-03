import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { MetricsModule } from '../metrics/metrics.module';
import { EgoMonitorService } from './ego-monitor.service';

@Module({
  imports: [ConfigModule, MetricsModule],
  providers: [EgoMonitorService],
})
export class EgoMonitorModule {}
