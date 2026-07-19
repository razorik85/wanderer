import { MassState, Passage } from '@/hooks/Mapper/types';

const WORMHOLE_MASS_VARIANCE = 0.1;

export type MassBalanceStatus = 'Stable' | 'Reduced' | 'Critical' | 'Collapsed';

export type MassBalance = {
  confirmedMass: number;
  estimatedOpenMass: number;
  trackedMass: number;
  remainingMinimum: number | null;
  remainingMaximum: number | null;
  statusMinimum: MassBalanceStatus | null;
  statusMaximum: MassBalanceStatus | null;
};

export type ReconciledMassRange = {
  compatible: boolean;
  minimum: number | null;
  maximum: number | null;
};

const getPassageMass = (passage: Passage) => {
  const mass = passage.mass ?? parseInt(passage.ship.ship_type_info.mass);
  return Number.isFinite(mass) && mass > 0 ? mass : 0;
};

const getStatus = (remainingMass: number, nominalMass: number): MassBalanceStatus => {
  const remainingRatio = remainingMass / nominalMass;

  if (remainingMass <= 0) return 'Collapsed';
  if (remainingRatio <= 0.1) return 'Critical';
  if (remainingRatio <= 0.5) return 'Reduced';
  return 'Stable';
};

export const calculateMassBalance = (passages: Passage[], nominalMass?: number | null): MassBalance => {
  const confirmedMass = passages
    .filter(passage => passage.mass_confirmed_at != null)
    .reduce((sum, passage) => sum + getPassageMass(passage), 0);
  const estimatedOpenMass = passages
    .filter(passage => passage.mass_confirmed_at == null)
    .reduce((sum, passage) => sum + getPassageMass(passage), 0);
  const trackedMass = confirmedMass + estimatedOpenMass;

  if (!nominalMass || nominalMass <= 0) {
    return {
      confirmedMass,
      estimatedOpenMass,
      trackedMass,
      remainingMinimum: null,
      remainingMaximum: null,
      statusMinimum: null,
      statusMaximum: null,
    };
  }

  const remainingMinimum = Math.max(nominalMass * (1 - WORMHOLE_MASS_VARIANCE) - trackedMass, 0);
  const remainingMaximum = Math.max(nominalMass * (1 + WORMHOLE_MASS_VARIANCE) - trackedMass, 0);

  return {
    confirmedMass,
    estimatedOpenMass,
    trackedMass,
    remainingMinimum,
    remainingMaximum,
    statusMinimum: getStatus(remainingMinimum, nominalMass * (1 - WORMHOLE_MASS_VARIANCE)),
    statusMaximum: getStatus(remainingMaximum, nominalMass * (1 + WORMHOLE_MASS_VARIANCE)),
  };
};

export const reconcileMassRange = (
  balance: MassBalance,
  nominalMass: number | null,
  observedStatus: MassState,
): ReconciledMassRange => {
  if (nominalMass == null || balance.remainingMinimum == null || balance.remainingMaximum == null) {
    return { compatible: false, minimum: null, maximum: null };
  }

  const possibleCapacityMinimum = nominalMass * (1 - WORMHOLE_MASS_VARIANCE);
  const possibleCapacityMaximum = nominalMass * (1 + WORMHOLE_MASS_VARIANCE);
  const trackedMass = balance.trackedMass;

  // EVE reports the status after the passage. Constrain the possible actual
  // capacity first, then subtract the mass of every passage including the new one.
  const observedCapacityBounds: Record<MassState, [number, number]> = {
    [MassState.normal]: [trackedMass * 2, possibleCapacityMaximum],
    [MassState.half]: [trackedMass / 0.9, trackedMass * 2],
    [MassState.verge]: [trackedMass, trackedMass / 0.9],
  };
  const [observedCapacityMinimum, observedCapacityMaximum] = observedCapacityBounds[observedStatus];
  const capacityMinimum = Math.max(possibleCapacityMinimum, observedCapacityMinimum);
  const capacityMaximum = Math.min(possibleCapacityMaximum, observedCapacityMaximum);
  const minimum = Math.max(capacityMinimum - trackedMass, 0);
  const maximum = Math.max(capacityMaximum - trackedMass, 0);

  return capacityMinimum <= capacityMaximum
    ? { compatible: true, minimum, maximum }
    : { compatible: false, minimum: null, maximum: null };
};
