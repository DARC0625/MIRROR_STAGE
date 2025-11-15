import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { MetricsService } from './metrics.service';
import { MetricsBatchSchema, type MetricsBatch } from './metrics.dto';
import { ZodValidationPipe } from 'nestjs-zod';

/** 에이전트가 메트릭 샘플을 업로드하는 REST 엔드포인트. */
@Controller('metrics')
export class MetricsController {
  constructor(private readonly metricsService: MetricsService) {}

  /** POST /metrics/batch → 샘플 묶음 수신 */
  @Post('batch')
  @HttpCode(HttpStatus.ACCEPTED)
  async ingestBatch(@Body(new ZodValidationPipe(MetricsBatchSchema)) body: MetricsBatch) {
    const accepted = await this.metricsService.ingestBatch(body.samples);
    return {
      accepted,
      receivedAt: new Date().toISOString(),
    };
  }
}
