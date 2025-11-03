import { Column, CreateDateColumn, Entity, PrimaryColumn, UpdateDateColumn } from 'typeorm';

@Entity({ name: 'host_metrics' })
export class HostMetricEntity {
  @PrimaryColumn({ type: 'varchar', length: 120 })
  hostname!: string;

  @Column({ type: 'varchar', length: 120 })
  displayName!: string;

  @Column({ type: 'varchar', length: 64, nullable: true })
  ip!: string | null;

  @Column({ type: 'varchar', length: 64, nullable: true })
  rack!: string | null;

  @Column({ type: 'varchar', length: 64 })
  platform!: string;

  @Column({ type: 'varchar', length: 64 })
  agentVersion!: string;

  @Column({ type: 'float', default: 0 })
  cpuLoad!: number;

  @Column({ type: 'float', default: 0 })
  memoryUsedPercent!: number;

  @Column({ type: 'float', default: 0 })
  loadAverage!: number;

  @Column({ type: 'integer', default: 0 })
  uptimeSeconds!: number;

  @Column({ type: 'float', nullable: true })
  gpuTemperature!: number | null;

  @Column({ type: 'integer', nullable: true })
  netBytesTx!: number | null;

  @Column({ type: 'integer', nullable: true })
  netBytesRx!: number | null;

  @Column({ type: 'float', nullable: true })
  netThroughputGbps!: number | null;

  @Column({ type: 'float', nullable: true })
  netCapacityGbps!: number | null;

  @Column({ type: 'simple-json', nullable: true })
  tags!: Record<string, string> | null;

  @Column({ type: 'float', nullable: true })
  positionX!: number | null;

  @Column({ type: 'float', nullable: true })
  positionY!: number | null;

  @Column({ type: 'float', nullable: true })
  positionZ!: number | null;

  @Column()
  lastSeen!: Date;

  @CreateDateColumn()
  createdAt!: Date;

  @UpdateDateColumn()
  updatedAt!: Date;
}
