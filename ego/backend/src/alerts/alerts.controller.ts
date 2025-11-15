import { Controller, Get } from '@nestjs/common';
import { AlertsService } from './alerts.service';

/** 알람 조회 REST 엔드포인트 */
@Controller('alerts')
export class AlertsController {
  constructor(private readonly alertsService: AlertsService) {}

  /** GET /alerts/active → 활성 경보 목록 */
  @Get('active')
  getActiveAlerts() {
    return this.alertsService.getActiveAlerts();
  }
}
