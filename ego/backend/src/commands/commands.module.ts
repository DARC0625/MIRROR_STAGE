import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { CommandEntity } from './command.entity';
import { CommandsService } from './commands.service';
import { CommandsController } from './commands.controller';
import { CommandsGateway } from './commands.gateway';

/**
 * 명령 큐/게이트웨이 기능을 묶는 Nest 모듈.
 */
@Module({
  imports: [TypeOrmModule.forFeature([CommandEntity])],
  providers: [CommandsService, CommandsGateway],
  controllers: [CommandsController],
  exports: [CommandsService],
})
export class CommandsModule {}
