import { Module } from '@nestjs/common';
import { MetricsController } from './metrics.controller';
import { MetricsService } from './metrics.service';
import { DigitalTwinModule } from '../twin/digital-twin.module';

@Module({
  imports: [DigitalTwinModule],
  controllers: [MetricsController],
  providers: [MetricsService],
})
export class MetricsModule {}
