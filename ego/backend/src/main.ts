import 'reflect-metadata';
import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { ZodValidationPipe } from 'nestjs-zod';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, {
    cors: {
      origin: true,
      credentials: true,
      exposedHeaders: ['x-request-id'],
    },
  });

  app.setGlobalPrefix('api');
  app.useGlobalPipes(new ZodValidationPipe());

  const port = Number(process.env.PORT ?? 3000);
  await app.listen(port);
  Logger.log(`🚀 MIRROR STAGE EGO backend listening on http://localhost:${port}`, 'Bootstrap');
}
bootstrap().catch((error) => {
  Logger.error(error, 'Bootstrap');
  process.exit(1);
});
