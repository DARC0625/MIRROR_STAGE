import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { MetricsModule } from './metrics/metrics.module';
import { DigitalTwinModule } from './twin/digital-twin.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
    }),
    DigitalTwinModule,
    MetricsModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
