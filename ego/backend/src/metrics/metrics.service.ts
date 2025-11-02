import { Injectable } from '@nestjs/common';
import { DigitalTwinService } from '../twin/digital-twin.service';
import type { MetricSample } from './metrics.dto';

@Injectable()
export class MetricsService {
  constructor(private readonly twinService: DigitalTwinService) {}

  ingestBatch(samples: MetricSample[]): number {
    for (const sample of samples) {
      this.twinService.ingestSample(sample);
    }
    return samples.length;
  }
}
