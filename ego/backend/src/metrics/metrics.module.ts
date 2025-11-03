import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { MetricsController } from './metrics.controller';
import { MetricsService } from './metrics.service';
import { DigitalTwinModule } from '../twin/digital-twin.module';
import { HostMetricEntity } from '../persistence/host-metric.entity';

@Module({
  imports: [DigitalTwinModule, TypeOrmModule.forFeature([HostMetricEntity])],
  controllers: [MetricsController],
  providers: [MetricsService],
})
export class MetricsModule {}
