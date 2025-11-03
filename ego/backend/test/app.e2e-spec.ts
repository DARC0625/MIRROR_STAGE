import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import request from 'supertest';
import type { App } from 'supertest/types';
import { ZodValidationPipe } from 'nestjs-zod';
import { AppModule } from '../src/app.module';
import { HostMetricEntity } from '../src/persistence/host-metric.entity';
import type { Repository } from 'typeorm';

describe('Digital Twin API (e2e)', () => {
  let app: INestApplication<App>;
  let repository: Repository<HostMetricEntity>;

  beforeAll(async () => {
    process.env.NODE_ENV = 'test';

    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.setGlobalPrefix('api');
    app.useGlobalPipes(new ZodValidationPipe());
    await app.init();

    repository = app.get<Repository<HostMetricEntity>>(getRepositoryToken(HostMetricEntity));
  });

  afterAll(async () => {
    await app.close();
  });

  it('responds with health status', async () => {
    await request(app.getHttpServer()).get('/api/health').expect(200).expect('ok');
  });

  it('ingests metrics, raises alerts, and exposes digital twin state', async () => {
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

    const records = await repository.find();
    expect(records).toHaveLength(1);
    expect(records[0].hostname).toBe('titan-01');
    expect(records[0].cpuLoad).toBeCloseTo(42.5);
    expect(records[0].netBytesTx).toBe(1_250_000_000);

    const alertPayload = {
      samples: [
        {
          hostname: 'titan-01',
          timestamp: new Date().toISOString(),
          cpu_load: 95,
          memory_used_percent: 96,
          load_average: 4.2,
          uptime_seconds: 8200,
          agent_version: '0.1.0-dev',
          platform: 'Linux-x86_64',
          net_bytes_tx: 2_500_000_000,
          net_bytes_rx: 2_100_000_000,
        },
      ],
    };

    await request(app.getHttpServer())
      .post('/api/metrics/batch')
      .send(alertPayload)
      .expect(202);

    const alertsResponse = await request(app.getHttpServer()).get('/api/alerts/active').expect(200);
    expect(Array.isArray(alertsResponse.body)).toBe(true);
    expect(alertsResponse.body.length).toBeGreaterThanOrEqual(1);
    expect(alertsResponse.body[0].hostname).toBe('titan-01');

    const createCommandResponse = await request(app.getHttpServer())
      .post('/api/commands')
      .send({ hostname: 'titan-01', command: 'echo hello', timeoutSeconds: 5 })
      .expect(201);

    expect(createCommandResponse.body.hostname).toBe('titan-01');
    const commandId = createCommandResponse.body.id;

    const pendingResponse = await request(app.getHttpServer())
      .get('/api/commands/pending/titan-01')
      .expect(200);
    expect(Array.isArray(pendingResponse.body)).toBe(true);
    expect(pendingResponse.body[0].id).toBe(commandId);
    expect(pendingResponse.body[0].command).toBe('echo hello');

    await request(app.getHttpServer())
      .post(`/api/commands/${commandId}/result`)
      .send({ status: 'succeeded', exitCode: 0, stdout: 'hello\n', stderr: '' })
      .expect(201);

    const emptyPending = await request(app.getHttpServer())
      .get('/api/commands/pending/titan-01')
      .expect(200);
    expect(emptyPending.body).toEqual([]);
  });
});
