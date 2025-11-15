import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { ZodValidationPipe } from 'nestjs-zod';
import { CommandsService } from './commands.service';
import {
  CreateCommandDto,
  CreateCommandSchema,
  CommandResultDto,
  CommandResultSchema,
  ListCommandsQueryDto,
  ListCommandsQuerySchema,
} from './commands.dto';

/**
 * 명령 REST API: 명령 생성, 결과 제출, 대기 목록 조회를 제공한다.
 */
@Controller('commands')
export class CommandsController {
  constructor(private readonly commandsService: CommandsService) {}

  /** POST /commands → 새 명령 생성 */
  @Post()
  create(@Body(new ZodValidationPipe(CreateCommandSchema)) dto: CreateCommandDto) {
    return this.commandsService.createCommand(dto);
  }

  /** 에이전트가 자신의 pending 명령을 가져갈 때 호출 */
  @Get('pending/:hostname')
  getPending(@Param('hostname') hostname: string) {
    return this.commandsService.getPendingCommands(hostname);
  }

  /** 명령 실행 결과 업로드 */
  @Post(':id/result')
  submitResult(
    @Param('id') id: string,
    @Body(new ZodValidationPipe(CommandResultSchema)) dto: CommandResultDto,
  ) {
    return this.commandsService.submitResult(id, dto);
  }

  /** 명령 이력 목록 (필터/검색/페이지네이션 지원) */
  @Get()
  list(@Query(new ZodValidationPipe(ListCommandsQuerySchema)) query: ListCommandsQueryDto) {
    return this.commandsService.paginateCommands(query);
  }
}
