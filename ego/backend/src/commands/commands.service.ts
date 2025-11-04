import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Subject } from 'rxjs';
import { CommandEntity, CommandStatus } from './command.entity';
import { CreateCommandDto, CommandResultDto, ListCommandsQueryDto } from './commands.dto';

export interface PendingCommandPayload {
  id: string;
  command: string;
  timeoutSeconds: number | null;
}

export interface CommandUpdateEvent {
  id: string;
  hostname: string;
  status: CommandStatus;
  exitCode?: number | null;
  stdout?: string | null;
  stderr?: string | null;
}

@Injectable()
export class CommandsService {
  private readonly updatesSubject = new Subject<CommandUpdateEvent>();
  readonly updates$ = this.updatesSubject.asObservable();

  constructor(
    @InjectRepository(CommandEntity)
    private readonly commandsRepository: Repository<CommandEntity>,
  ) {}

  async createCommand(dto: CreateCommandDto): Promise<CommandEntity> {
    const command = this.commandsRepository.create({
      hostname: dto.hostname,
      command: dto.command,
      timeoutSeconds: dto.timeoutSeconds ?? null,
      metadata: dto.metadata ?? null,
      status: 'pending',
    });
    const saved = await this.commandsRepository.save(command);
    this.publishUpdate(saved);
    return saved;
  }

  async getPendingCommands(hostname: string, limit = 5): Promise<PendingCommandPayload[]> {
    const pending = await this.commandsRepository.find({
      where: { hostname, status: 'pending' },
      order: { requestedAt: 'ASC' },
      take: limit,
    });

    if (pending.length === 0) {
      return [];
    }

    for (const command of pending) {
      command.status = 'running';
      command.startedAt = new Date();
      await this.commandsRepository.save(command);
      this.publishUpdate(command);
    }

    return pending.map((command) => ({
      id: command.id,
      command: command.command,
      timeoutSeconds: command.timeoutSeconds,
    }));
  }

  async submitResult(id: string, dto: CommandResultDto): Promise<CommandEntity> {
    const command = await this.commandsRepository.findOne({ where: { id } });
    if (!command) {
      throw new NotFoundException(`Command ${id} not found`);
    }

    command.status = dto.status;
    command.completedAt = new Date();
    command.exitCode = dto.exitCode ?? null;
    command.stdout = dto.stdout ?? null;
    command.stderr = dto.stderr ?? null;
    await this.commandsRepository.save(command);
    this.publishUpdate(command);
    return command;
  }

  async paginateCommands(query: ListCommandsQueryDto) {
    const qb = this.commandsRepository.createQueryBuilder('command').orderBy('command.requestedAt', 'DESC');

    if (query.hostname) {
      qb.andWhere('command.hostname = :hostname', { hostname: query.hostname });
    }
    if (query.status) {
      qb.andWhere('command.status = :status', { status: query.status });
    }
    if (query.search) {
      qb.andWhere('LOWER(command.command) LIKE :search', { search: `%${query.search.toLowerCase()}%` });
    }

    const total = await qb.getCount();
    const page = query.page ?? 1;
    const pageSize = query.pageSize ?? 20;
    const items = await qb.skip((page - 1) * pageSize).take(pageSize).getMany();

    return {
      items,
      total,
      page,
      pageSize,
    };
  }

  private publishUpdate(command: CommandEntity): void {
    this.updatesSubject.next({
      id: command.id,
      hostname: command.hostname,
      status: command.status,
      exitCode: command.exitCode,
      stdout: command.stdout,
      stderr: command.stderr,
    });
  }
}
