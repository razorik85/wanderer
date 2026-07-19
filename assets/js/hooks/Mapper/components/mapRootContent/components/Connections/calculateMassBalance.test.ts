import { Passage } from '@/hooks/Mapper/types';
import { calculateMassBalance } from './calculateMassBalance.ts';

const passage = (mass: number, confirmed: boolean): Passage =>
  ({
    id: `${mass}-${confirmed}`,
    mass,
    mass_confirmed_at: confirmed ? '2026-07-19T12:00:00Z' : null,
    mass_confirmed_by_id: confirmed ? 'user-id' : null,
  }) as Passage;

describe('calculateMassBalance', () => {
  it('separates confirmed mass and open estimates', () => {
    const result = calculateMassBalance([passage(100_000_000, true), passage(200_000_000, false)], 1_000_000_000);

    expect(result.confirmedMass).toBe(100_000_000);
    expect(result.estimatedOpenMass).toBe(200_000_000);
    expect(result.trackedMass).toBe(300_000_000);
    expect(result.remainingMinimum).toBe(600_000_000);
    expect(result.remainingMaximum).toBe(800_000_000);
    expect(result.statusMinimum).toBe('Stable');
    expect(result.statusMaximum).toBe('Stable');
  });

  it('reports a status range when the natural mass variance crosses a threshold', () => {
    const result = calculateMassBalance([passage(850_000_000, true)], 1_000_000_000);

    expect(result.remainingMinimum).toBe(50_000_000);
    expect(result.remainingMaximum).toBe(250_000_000);
    expect(result.statusMinimum).toBe('Critical');
    expect(result.statusMaximum).toBe('Reduced');
  });

  it('does not derive remaining mass for an unknown wormhole type', () => {
    const result = calculateMassBalance([passage(100_000_000, true)], null);

    expect(result.trackedMass).toBe(100_000_000);
    expect(result.remainingMinimum).toBeNull();
    expect(result.remainingMaximum).toBeNull();
    expect(result.statusMinimum).toBeNull();
    expect(result.statusMaximum).toBeNull();
  });
});
