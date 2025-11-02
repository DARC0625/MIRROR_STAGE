import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ServeStaticModule } from '@nestjs/serve-static';
import { join } from 'path';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { MetricsModule } from './metrics/metrics.module';
import { DigitalTwinModule } from './twin/digital-twin.module';

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
    DigitalTwinModule,
    MetricsModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
