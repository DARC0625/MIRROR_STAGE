import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';

export const CreateCommandSchema = z.object({
  hostname: z.string().min(1),
  command: z.string().min(1),
  timeoutSeconds: z.number().positive().max(600).optional(),
  metadata: z.record(z.any()).optional(),
});

export class CreateCommandDto extends createZodDto(CreateCommandSchema) {}

export const CommandResultSchema = z.object({
  status: z.enum(['succeeded', 'failed', 'timeout']),
  stdout: z.string().optional(),
  stderr: z.string().optional(),
  exitCode: z.number().int().optional(),
  durationSeconds: z.number().nonnegative().optional(),
});

export class CommandResultDto extends createZodDto(CommandResultSchema) {}
