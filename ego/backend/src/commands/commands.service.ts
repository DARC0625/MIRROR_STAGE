import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Subject } from 'rxjs';
import { CommandEntity, CommandStatus } from './command.entity';
import { CreateCommandDto, CommandResultDto, ListCommandsQueryDto } from './commands.dto';

/**
 * 에이전트에게 전달할 명령 페이로드 (실행 대기 상태).
 */
export interface PendingCommandPayload {
  id: string;
  command: string;
  timeoutSeconds: number | null;
}

/**
 * 명령 상태가 변경될 때 실시간 브로드캐스트되는 이벤트.
 */
export interface CommandUpdateEvent {
  id: string;
  hostname: string;
  status: CommandStatus;
  exitCode?: number | null;
  stdout?: string | null;
  stderr?: string | null;
}

/**
 * 명령 큐/이력 관리를 담당하는 서비스.
 * - 명령 작성/수행/결과 저장
 * - 페이징 API 지원
 * - RxJS Subject 로 실시간 상태 스트림 제공
 */
@Injectable()
export class CommandsService {
  private readonly updatesSubject = new Subject<CommandUpdateEvent>();
  readonly updates$ = this.updatesSubject.asObservable();

  constructor(
    @InjectRepository(CommandEntity)
    private readonly commandsRepository: Repository<CommandEntity>,
  ) {}

  /** 새 명령을 생성하고 pending 상태로 큐에 넣는다. */
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

  /**
   * 특정 호스트가 가져갈 pending 명령 목록을 반환한다.
   * 반환 시 running 으로 전환하여 중복 실행을 방지한다.
   */
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

  /**
   * 에이전트가 전달한 명령 실행 결과를 저장한다.
   */
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

  /**
   * 필터/검색 조건에 따라 명령 이력을 페이지 단위로 반환한다.
   */
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

  /** 상태 변경을 updates$ 스트림으로 흘려보낸다. */
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
