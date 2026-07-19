import { Passage } from '@/hooks/Mapper/types';
import { calculatePolarizations, formatPolarizationRemaining } from './calculatePolarization.ts';

const passage = (from: boolean, insertedAt: string, characterId = '42'): Passage =>
  ({
    id: `${from}-${insertedAt}`,
    from,
    inserted_at: insertedAt,
    character: { eve_id: characterId, name: `Pilot ${characterId}` },
  }) as Passage;

describe('calculatePolarizations', () => {
  const now = new Date('2026-07-19T12:05:00Z').getTime();

  it('shows a one-way traversal as partial polarization', () => {
    expect(calculatePolarizations([passage(true, '2026-07-19T12:03:00Z')], now)[0]).toMatchObject({ state: 'partial' });
  });

  it('shows a quick return as fully polarized until the first directional timer expires', () => {
    const result = calculatePolarizations(
      [passage(true, '2026-07-19T12:01:00Z'), passage(false, '2026-07-19T12:03:00Z')],
      now,
    );

    expect(result[0]).toMatchObject({ state: 'polarized', expiresAt: new Date('2026-07-19T12:06:00Z').getTime() });
  });

  it('drops expired polarization', () => {
    const oldPassage = passage(true, '2026-07-19T11:45:00Z');
    expect(calculatePolarizations([oldPassage], now)).toEqual([]);
  });

  it('formats a stable countdown', () => {
    expect(formatPolarizationRemaining(now + 125_000, now)).toBe('2:05');
  });
});
