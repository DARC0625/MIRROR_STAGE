import { Injectable } from '@nestjs/common';
import { OnModuleDestroy, OnModuleInit } from '@nestjs/common/interfaces';
import { WebSocketGateway, WebSocketServer } from '@nestjs/websockets';
import type { Server } from 'socket.io';
import { Subscription } from 'rxjs';
import { CommandsService } from './commands.service';

@Injectable()
@WebSocketGateway({ namespace: 'commands', cors: { origin: '*' } })
export class CommandsGateway implements OnModuleInit, OnModuleDestroy {
  @WebSocketServer()
  server!: Server;

  private subscription?: Subscription;

  constructor(private readonly commandsService: CommandsService) {}

  onModuleInit(): void {
    this.subscription = this.commandsService.updates$.subscribe((event) => {
      this.server.emit('command-update', event);
    });
  }

  onModuleDestroy(): void {
    this.subscription?.unsubscribe();
  }
}
