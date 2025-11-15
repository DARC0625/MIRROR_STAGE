import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';

/** 명령 상태 enum 정의(Zod). */
export const CommandStatusSchema = z.enum(['pending', 'running', 'succeeded', 'failed', 'timeout']);

export const CreateCommandSchema = z.object({
  hostname: z.string().min(1),
  command: z.string().min(1),
  timeoutSeconds: z.number().positive().max(600).optional(),
  metadata: z.record(z.any()).optional(),
});

/** 명령 생성 DTO */
export class CreateCommandDto extends createZodDto(CreateCommandSchema) {}

export const CommandResultSchema = z.object({
  status: z.enum(['succeeded', 'failed', 'timeout']),
  stdout: z.string().optional(),
  stderr: z.string().optional(),
  exitCode: z.number().int().optional(),
  durationSeconds: z.number().nonnegative().optional(),
});

/** 명령 실행 결과 DTO */
export class CommandResultDto extends createZodDto(CommandResultSchema) {}

export const ListCommandsQuerySchema = z.object({
  hostname: z.string().min(1).optional(),
  status: CommandStatusSchema.optional(),
  search: z.string().min(1).optional(),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),
});

/** 명령 이력 필터/검색 DTO */
export class ListCommandsQueryDto extends createZodDto(ListCommandsQuerySchema) {}
