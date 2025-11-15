import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AlertEntity } from './alert.entity';
import { AlertsService } from './alerts.service';
import { AlertsController } from './alerts.controller';

/** 알람 생성/조회 기능을 제공하는 Nest 모듈 */
@Module({
  imports: [TypeOrmModule.forFeature([AlertEntity])],
  providers: [AlertsService],
  controllers: [AlertsController],
  exports: [AlertsService],
})
export class AlertsModule {}
