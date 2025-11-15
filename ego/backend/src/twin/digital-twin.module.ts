import { Module } from '@nestjs/common';
import { DigitalTwinService } from './digital-twin.service';
import { DigitalTwinGateway } from './digital-twin.gateway';
import { DigitalTwinController } from './digital-twin.controller';

/**
 * 디지털 트윈 관련 서비스/게이트웨이/컨트롤러를 묶는 Nest 모듈.
 */
@Module({
  providers: [DigitalTwinService, DigitalTwinGateway],
  controllers: [DigitalTwinController],
  exports: [DigitalTwinService],
})
export class DigitalTwinModule {}
