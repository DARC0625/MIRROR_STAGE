import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { ServeStaticModule } from '@nestjs/serve-static';
import { ScheduleModule } from '@nestjs/schedule';
import { TypeOrmModule } from '@nestjs/typeorm';
import { join } from 'path';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { MetricsModule } from './metrics/metrics.module';
import { DigitalTwinModule } from './twin/digital-twin.module';
import { HostMetricEntity } from './persistence/host-metric.entity';
import { HostMetricSampleEntity } from './persistence/host-metric-sample.entity';
import { CacheModule } from './cache/cache.module';
import { EgoMonitorModule } from './ego-monitor/ego-monitor.module';
import { AlertEntity } from './alerts/alert.entity';
import { AlertsModule } from './alerts/alerts.module';
import { CommandEntity } from './commands/command.entity';
import { CommandsModule } from './commands/commands.module';

@Module({
  imports: [
    ServeStaticModule.forRoot({
      rootPath: join(__dirname, '..', '..', 'frontend', 'build', 'web'),
      renderPath: '/',
      exclude: [
        '/api',
        '/api/(.*)',
        '/digital-twin',
        '/digital-twin/(.*)',
        '/socket.io',
        '/socket.io/(.*)',
      ],
      serveStaticOptions: {
        index: 'index.html',
      },
    }),
    ConfigModule.forRoot({
      isGlobal: true,
    }),
    ScheduleModule.forRoot(),
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => {
        const postgresUrl = config.get<string>('MIRROR_STAGE_DB_URL');
        const isTest = config.get<string>('NODE_ENV') === 'test' || process.env.JEST_WORKER_ID !== undefined;

        if (postgresUrl) {
          return {
            type: 'postgres',
            url: postgresUrl,
            entities: [HostMetricEntity, HostMetricSampleEntity, AlertEntity, CommandEntity],
            synchronize: true,
            ssl: config.get('MIRROR_STAGE_DB_SSL') === 'true',
          };
        }

        const sqlitePath =
          isTest || config.get<string>('MIRROR_STAGE_DB_IN_MEMORY') === 'true'
            ? ':memory:'
            : config.get<string>('MIRROR_STAGE_SQLITE_PATH') ?? join(process.cwd(), 'mirror_stage.db');

        return {
          type: 'sqlite',
          database: sqlitePath,
          entities: [HostMetricEntity, HostMetricSampleEntity, AlertEntity, CommandEntity],
          synchronize: true,
        };
      },
    }),
    CacheModule,
    DigitalTwinModule,
    MetricsModule,
    EgoMonitorModule,
    AlertsModule,
    CommandsModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
