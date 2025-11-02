import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import type { App } from 'supertest/types';
import { ZodValidationPipe } from 'nestjs-zod';
import { AppModule } from '../src/app.module';

describe('Digital Twin API (e2e)', () => {
  let app: INestApplication<App>;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.setGlobalPrefix('api');
    app.useGlobalPipes(new ZodValidationPipe());
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  it('responds with health status', async () => {
    await request(app.getHttpServer()).get('/api/health').expect(200).expect('ok');
  });

  it('ingests metrics and exposes digital twin state', async () => {
    const payload = {
      samples: [
        {
          hostname: 'titan-01',
          timestamp: new Date().toISOString(),
          cpu_load: 42.5,
          memory_used_percent: 63.2,
          load_average: 1.75,
          uptime_seconds: 7200,
          agent_version: '0.1.0-dev',
          platform: 'Linux-x86_64',
          net_bytes_tx: 1250000000,
          net_bytes_rx: 980000000,
        },
      ],
    };

    await request(app.getHttpServer())
      .post('/api/metrics/batch')
      .send(payload)
      .expect(202)
      .expect(({ body }) => {
        expect(body.accepted).toBe(1);
        expect(body.receivedAt).toBeDefined();
      });

    const { body } = await request(app.getHttpServer()).get('/api/twin/state').expect(200);

    expect(body.type).toBe('twin-state');
    expect(Array.isArray(body.hosts)).toBe(true);
    expect(body.hosts.length).toBeGreaterThanOrEqual(2);
    const host = body.hosts.find((entry: any) => entry.hostname === 'titan-01');
    expect(host).toBeDefined();
    expect(host.status).toBe('online');
    expect(Array.isArray(body.links)).toBe(true);
    expect(body.links.some((link: any) => link.target === 'titan-01')).toBeTruthy();
  });
});
