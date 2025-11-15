import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { OnGatewayConnection, WebSocketGateway, WebSocketServer } from '@nestjs/websockets';
import type { Server, Socket } from 'socket.io';
import { Subscription } from 'rxjs';
import { DigitalTwinService } from './digital-twin.service';

/**
 * WebSocket 게이트웨이: 디지털 트윈 스냅샷을 실시간으로 브로드캐스트한다.
 */
@Injectable()
@WebSocketGateway({
  cors: { origin: '*' },
  namespace: 'digital-twin',
})
export class DigitalTwinGateway implements OnModuleInit, OnModuleDestroy, OnGatewayConnection {
  @WebSocketServer()
  private server!: Server;

  private subscription?: Subscription;

  constructor(private readonly twinService: DigitalTwinService) {}

  /** 모듈 초기화 시 스냅샷 스트림을 WebSocket 으로 중계한다. */
  onModuleInit(): void {
    this.subscription = this.twinService.updates$.subscribe((snapshot) => {
      this.server?.emit('twin-state', snapshot);
    });
  }

  /** 새 클라이언트가 붙으면 즉시 최신 상태를 한번 푸시한다. */
  handleConnection(client: Socket) {
    client.emit('twin-state', this.twinService.getSnapshot());
  }

  /** 종료 시 구독을 정리한다. */
  onModuleDestroy(): void {
    this.subscription?.unsubscribe();
  }
}
