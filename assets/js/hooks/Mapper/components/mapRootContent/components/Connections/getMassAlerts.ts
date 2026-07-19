import { MassState } from '@/hooks/Mapper/types';
import { MassBalance, MassBalanceStatus, ReconciledMassRange } from './calculateMassBalance.ts';

export type MassAlert = { level: 'hint' | 'warning' | 'danger'; text: string };

const statusRank: Record<MassBalanceStatus, number> = { Stable: 0, Reduced: 1, Critical: 2, Collapsed: 3 };
const observedRank: Record<MassState, number> = {
  [MassState.normal]: 0,
  [MassState.half]: 1,
  [MassState.verge]: 2,
};

export const getMassAlerts = (
  balance: MassBalance,
  maxJumpMass: number | null,
  observedStatus: MassState,
  reconciled: ReconciledMassRange,
): MassAlert[] => {
  if (balance.remainingMinimum == null || balance.remainingMaximum == null) return [];

  const alerts: MassAlert[] = [];
  const worstStatus = balance.statusMinimum;
  const bestStatus = balance.statusMaximum;

  if (worstStatus === 'Collapsed') {
    alerts.push({
      level: bestStatus === 'Collapsed' ? 'danger' : 'warning',
      text:
        bestStatus === 'Collapsed' ? 'Calculated mass is exhausted.' : 'Collapse is possible within the mass variance.',
    });
  } else if (worstStatus === 'Critical') {
    alerts.push({ level: 'danger', text: 'Critical mass is possible; plan the next traversal carefully.' });
  } else if (worstStatus === 'Reduced') {
    alerts.push({ level: 'warning', text: 'Reduced mass is possible within the current estimate.' });
  }

  if (maxJumpMass && maxJumpMass > 0 && balance.remainingMinimum <= maxJumpMass && balance.remainingMaximum > 0) {
    alerts.push({ level: 'danger', text: 'One maximum-mass traversal could collapse this wormhole.' });
  }

  if (balance.estimatedOpenMass > 0) {
    alerts.push({ level: 'hint', text: 'The range still includes unconfirmed passage estimates.' });
  }

  if (!reconciled.compatible && worstStatus && bestStatus) {
    const observed = observedRank[observedStatus];
    const calculatedWorst = Math.max(statusRank[worstStatus], statusRank[bestStatus]);
    const calculatedBest = Math.min(statusRank[worstStatus], statusRank[bestStatus]);

    if (observed > calculatedWorst) {
      alerts.push({
        level: 'warning',
        text: 'Observed degradation is higher than tracked: untracked external passages are likely.',
      });
    } else if (observed < calculatedBest) {
      alerts.push({
        level: 'hint',
        text: 'Observed degradation is lower than tracked: check ship mass, regeneration, or lifecycle start.',
      });
    } else {
      alerts.push({ level: 'warning', text: 'Observed status conflicts with the tracked passage mass.' });
    }
  }

  return alerts;
};
