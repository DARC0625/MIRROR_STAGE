import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { MetricsService } from './metrics.service';
import { MetricsBatchSchema, type MetricsBatch } from './metrics.dto';
import { ZodValidationPipe } from 'nestjs-zod';

@Controller('metrics')
export class MetricsController {
  constructor(private readonly metricsService: MetricsService) {}

  @Post('batch')
  @HttpCode(HttpStatus.ACCEPTED)
  ingestBatch(@Body(new ZodValidationPipe(MetricsBatchSchema)) body: MetricsBatch) {
    const accepted = this.metricsService.ingestBatch(body.samples);
    return {
      accepted,
      receivedAt: new Date().toISOString(),
    };
  }
}
