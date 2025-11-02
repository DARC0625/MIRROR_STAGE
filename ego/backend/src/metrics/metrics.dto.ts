import { z } from 'zod';

export const MetricPositionSchema = z
  .object({
    x: z.number(),
    y: z.number(),
    z: z.number().default(0),
  })
  .partial()
  .transform((value) => ({
    x: value.x ?? 0,
    y: value.y ?? 0,
    z: value.z ?? 0,
  }));

export const MetricSampleSchema = z
  .object({
    hostname: z.string().min(1),
    timestamp: z
      .string()
      .min(1)
      .refine((value) => !Number.isNaN(Date.parse(value)), 'Invalid ISO timestamp'),
    cpu_load: z.number().min(0),
    memory_used_percent: z.number().min(0).max(100),
    load_average: z.number(),
    uptime_seconds: z.number().nonnegative(),
    agent_version: z.string().min(1),
    platform: z.string().min(1),
    gpu_temperature: z.number().optional(),
    net_bytes_tx: z.number().nonnegative().optional(),
    net_bytes_rx: z.number().nonnegative().optional(),
    ipv4: z.string().ip({ version: 'v4' }).optional(),
    ip: z.string().ip({ version: 'v4' }).optional(),
    rack: z.string().optional(),
    position: MetricPositionSchema.optional(),
    tags: z.record(z.string()).optional(),
  })
  .passthrough();

export const MetricsBatchSchema = z.object({
    samples: z.array(MetricSampleSchema).min(1),
  });

export type MetricSample = z.infer<typeof MetricSampleSchema>;
export type MetricsBatch = z.infer<typeof MetricsBatchSchema>;
