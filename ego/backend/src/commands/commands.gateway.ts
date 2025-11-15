import { Injectable } from '@nestjs/common';
import { OnModuleDestroy, OnModuleInit } from '@nestjs/common/interfaces';
import { WebSocketGateway, WebSocketServer } from '@nestjs/websockets';
import type { Server } from 'socket.io';
import { Subscription } from 'rxjs';
import { CommandsService } from './commands.service';

/**
 * 명령 업데이트를 실시간으로 push 해주는 WebSocket 게이트웨이.
 */
@Injectable()
@WebSocketGateway({ namespace: 'commands', cors: { origin: '*' } })
export class CommandsGateway implements OnModuleInit, OnModuleDestroy {
  @WebSocketServer()
  server!: Server;

  private subscription?: Subscription;

  constructor(private readonly commandsService: CommandsService) {}

  /** 서비스 스트림을 구독하여 모든 클라이언트에게 브로드캐스트한다. */
  onModuleInit(): void {
    this.subscription = this.commandsService.updates$.subscribe((event) => {
      this.server.emit('command-update', event);
    });
  }

  /** 종료 시 스트림 구독 해제. */
  onModuleDestroy(): void {
    this.subscription?.unsubscribe();
  }
}
