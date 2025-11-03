import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { MetricsController } from './metrics.controller';
import { MetricsService } from './metrics.service';
import { DigitalTwinModule } from '../twin/digital-twin.module';
import { HostMetricEntity } from '../persistence/host-metric.entity';
import { HostMetricSampleEntity } from '../persistence/host-metric-sample.entity';
import { AlertsModule } from '../alerts/alerts.module';

@Module({
  imports: [DigitalTwinModule, AlertsModule, TypeOrmModule.forFeature([HostMetricEntity, HostMetricSampleEntity])],
  controllers: [MetricsController],
  providers: [MetricsService],
  exports: [MetricsService],
})
export class MetricsModule {}
