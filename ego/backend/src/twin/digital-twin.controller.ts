import { Controller, Get } from '@nestjs/common';
import { DigitalTwinService } from './digital-twin.service';

/**
 * REST 진입점: 최신 디지털 트윈 스냅샷을 읽어온다.
 */
@Controller('twin')
export class DigitalTwinController {
  constructor(private readonly twinService: DigitalTwinService) {}

  /** GET /twin/state → 현재 트윈 스냅샷 */
  @Get('state')
  getTwinState() {
    return this.twinService.getSnapshot();
  }
}
