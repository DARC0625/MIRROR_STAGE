import { Column, CreateDateColumn, Entity, Index, PrimaryGeneratedColumn, UpdateDateColumn } from 'typeorm';

export type AlertSeverity = 'info' | 'warning' | 'critical';
export type AlertStatus = 'active' | 'resolved';

@Entity({ name: 'alerts' })
@Index(['hostname', 'status'])
export class AlertEntity {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'varchar', length: 120 })
  hostname!: string;

  @Column({ type: 'varchar', length: 32 })
  severity!: AlertSeverity;

  @Column({ type: 'varchar', length: 64 })
  metric!: string;

  @Column({ type: 'varchar', length: 255 })
  message!: string;

  @Column({ type: 'float', nullable: true })
  threshold!: number | null;

  @Column({ type: 'float', nullable: true })
  currentValue!: number | null;

  @Column({ type: 'varchar', length: 16, default: 'active' })
  status!: AlertStatus;

  @CreateDateColumn()
  createdAt!: Date;

  @Column({ type: 'datetime', nullable: true })
  resolvedAt!: Date | null;

  @UpdateDateColumn()
  updatedAt!: Date;
}
