import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { ZodValidationPipe } from 'nestjs-zod';
import { CommandsService } from './commands.service';
import { CreateCommandDto, CreateCommandSchema, CommandResultDto, CommandResultSchema } from './commands.dto';

@Controller('commands')
export class CommandsController {
  constructor(private readonly commandsService: CommandsService) {}

  @Post()
  create(@Body(new ZodValidationPipe(CreateCommandSchema)) dto: CreateCommandDto) {
    return this.commandsService.createCommand(dto);
  }

  @Get('pending/:hostname')
  getPending(@Param('hostname') hostname: string) {
    return this.commandsService.getPendingCommands(hostname);
  }

  @Post(':id/result')
  submitResult(
    @Param('id') id: string,
    @Body(new ZodValidationPipe(CommandResultSchema)) dto: CommandResultDto,
  ) {
    return this.commandsService.submitResult(id, dto);
  }

  @Get()
  list() {
    return this.commandsService.listCommands();
  }
}
