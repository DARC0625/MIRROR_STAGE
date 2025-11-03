import { Column, CreateDateColumn, Entity, PrimaryGeneratedColumn, Index } from 'typeorm';

@Entity({ name: 'host_metric_samples' })
@Index(['hostname', 'timestamp'])
export class HostMetricSampleEntity {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'varchar', length: 120 })
  hostname!: string;

  @Column({ type: 'varchar', length: 120 })
  displayName!: string;

  @Column({ type: 'datetime' })
  timestamp!: Date;

  @Column({ type: 'float', default: 0 })
  cpuLoad!: number;

  @Column({ type: 'float', default: 0 })
  memoryUsedPercent!: number;

  @Column({ type: 'float', default: 0 })
  loadAverage!: number;

  @Column({ type: 'bigint', default: 0 })
  uptimeSeconds!: number;

  @Column({ type: 'float', nullable: true })
  gpuTemperature!: number | null;

  @Column({ type: 'float', nullable: true })
  cpuTemperature!: number | null;

  @Column({ type: 'bigint', nullable: true })
  memoryTotalBytes!: number | null;

  @Column({ type: 'bigint', nullable: true })
  memoryAvailableBytes!: number | null;

  @Column({ type: 'float', nullable: true })
  netThroughputGbps!: number | null;

  @Column({ type: 'float', nullable: true })
  netCapacityGbps!: number | null;

  @Column({ type: 'bigint', nullable: true })
  netBytesTx!: number | null;

  @Column({ type: 'bigint', nullable: true })
  netBytesRx!: number | null;

  @Column({ type: 'simple-json', nullable: true })
  tags!: Record<string, string> | null;

  @Column({ type: 'simple-json', nullable: true })
  position!: Record<string, unknown> | null;

  @CreateDateColumn()
  createdAt!: Date;
}
