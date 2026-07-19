import { Passage } from '@/hooks/Mapper/types';

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
    statusMinimum: getStatus(remainingMinimum, nominalMass),
    statusMaximum: getStatus(remainingMaximum, nominalMass),
  };
};
