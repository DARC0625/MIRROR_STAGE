import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { OnGatewayConnection, WebSocketGateway, WebSocketServer } from '@nestjs/websockets';
import type { Server, Socket } from 'socket.io';
import { Subscription } from 'rxjs';
import { DigitalTwinService } from './digital-twin.service';

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

  onModuleInit(): void {
    this.subscription = this.twinService.updates$.subscribe((snapshot) => {
      this.server?.emit('twin-state', snapshot);
    });
  }

  handleConnection(client: Socket) {
    client.emit('twin-state', this.twinService.getSnapshot());
  }

  onModuleDestroy(): void {
    this.subscription?.unsubscribe();
  }
}
