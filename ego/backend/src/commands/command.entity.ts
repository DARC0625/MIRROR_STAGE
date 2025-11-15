import { Column, CreateDateColumn, Entity, Index, PrimaryGeneratedColumn, UpdateDateColumn } from 'typeorm';

export type CommandStatus = 'pending' | 'running' | 'succeeded' | 'failed' | 'timeout';

/** 명령 큐를 나타내는 TypeORM Entity */
@Entity({ name: 'commands' })
@Index(['hostname', 'status'])
export class CommandEntity {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'varchar', length: 120 })
  hostname!: string;

  @Column({ type: 'text' })
  command!: string;

  @Column({ type: 'float', nullable: true })
  timeoutSeconds!: number | null;

  @Column({ type: 'varchar', length: 16, default: 'pending' })
  status!: CommandStatus;

  @Column({ type: 'datetime', nullable: true })
  startedAt!: Date | null;

  @Column({ type: 'datetime', nullable: true })
  completedAt!: Date | null;

  @Column({ type: 'integer', nullable: true })
  exitCode!: number | null;

  @Column({ type: 'text', nullable: true })
  stdout!: string | null;

  @Column({ type: 'text', nullable: true })
  stderr!: string | null;

  @Column({ type: 'simple-json', nullable: true })
  metadata!: Record<string, unknown> | null;

  @CreateDateColumn()
  requestedAt!: Date;

  @UpdateDateColumn()
  updatedAt!: Date;
}
