import { Global, Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { caching } from 'cache-manager';
import type { Cache } from 'cache-manager';
import { redisStore } from 'cache-manager-redis-yet';

export const CACHE_TOKEN = Symbol('MIRROR_STAGE_CACHE');

@Global()
@Module({
  imports: [ConfigModule],
  providers: [
    {
      provide: CACHE_TOKEN,
      inject: [ConfigService],
      useFactory: async (configService: ConfigService): Promise<Cache> => {
        const redisUrl = configService.get<string>('MIRROR_STAGE_REDIS_URL');

        if (redisUrl) {
          const store = await redisStore({
            url: redisUrl,
            ttl: 5_000,
          });
          return caching(store);
        }

        return caching('memory', {
          ttl: 5_000,
          max: 500,
        });
      },
    },
  ],
  exports: [CACHE_TOKEN],
})
export class CacheModule {}
