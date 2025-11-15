import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { MetricsModule } from '../metrics/metrics.module';
import { EgoMonitorService } from './ego-monitor.service';

/** EGO 자체 모니터링 서비스를 제공하는 모듈 */
@Module({
  imports: [ConfigModule, MetricsModule],
  providers: [EgoMonitorService],
})
export class EgoMonitorModule {}
