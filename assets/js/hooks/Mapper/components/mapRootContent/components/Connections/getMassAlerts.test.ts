import { MassState } from '@/hooks/Mapper/types';
import { MassBalance } from './calculateMassBalance.ts';
import { getMassAlerts } from './getMassAlerts.ts';

const balance = (overrides: Partial<MassBalance> = {}): MassBalance => ({
  confirmedMass: 800,
  estimatedOpenMass: 0,
  trackedMass: 800,
  regeneratedMass: 0,
  effectiveMass: 800,
  remainingMinimum: 50,
  remainingMaximum: 250,
  statusMinimum: 'Critical',
  statusMaximum: 'Reduced',
  ...overrides,
});

describe('getMassAlerts', () => {
  it('warns for critical mass and a potentially collapsing jump', () => {
    const alerts = getMassAlerts(balance(), 100, MassState.half, { compatible: true, minimum: 50, maximum: 250 });
    expect(alerts.map(alert => alert.text)).toEqual(
      expect.arrayContaining([expect.stringContaining('Critical mass'), expect.stringContaining('could collapse')]),
    );
  });

  it('identifies likely untracked external passages', () => {
    const stable = balance({ statusMinimum: 'Stable', statusMaximum: 'Stable' });
    const alerts = getMassAlerts(stable, null, MassState.verge, { compatible: false, minimum: null, maximum: null });
    expect(alerts.some(alert => alert.text.includes('external passages'))).toBe(true);
  });
});
