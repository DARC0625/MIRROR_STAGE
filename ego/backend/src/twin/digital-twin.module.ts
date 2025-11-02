import { Module } from '@nestjs/common';
import { DigitalTwinService } from './digital-twin.service';
import { DigitalTwinGateway } from './digital-twin.gateway';
import { DigitalTwinController } from './digital-twin.controller';

@Module({
  providers: [DigitalTwinService, DigitalTwinGateway],
  controllers: [DigitalTwinController],
  exports: [DigitalTwinService],
})
export class DigitalTwinModule {}
