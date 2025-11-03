import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { CommandEntity } from './command.entity';
import { CommandsService } from './commands.service';
import { CommandsController } from './commands.controller';
import { CommandsGateway } from './commands.gateway';

@Module({
  imports: [TypeOrmModule.forFeature([CommandEntity])],
  providers: [CommandsService, CommandsGateway],
  controllers: [CommandsController],
  exports: [CommandsService],
})
export class CommandsModule {}
