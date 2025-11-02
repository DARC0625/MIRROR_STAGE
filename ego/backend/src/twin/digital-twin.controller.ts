import { Controller, Get } from '@nestjs/common';
import { DigitalTwinService } from './digital-twin.service';

@Controller('twin')
export class DigitalTwinController {
  constructor(private readonly twinService: DigitalTwinService) {}

  @Get('state')
  getTwinState() {
    return this.twinService.getSnapshot();
  }
}
