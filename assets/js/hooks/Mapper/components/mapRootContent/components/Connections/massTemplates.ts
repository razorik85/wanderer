import { ShipMassTemplate } from '@/hooks/Mapper/types/options.ts';

export const getShipMassTemplates = (templates: ShipMassTemplate[] | undefined, shipTypeId: number) =>
  (templates ?? []).filter(template => template.ship_type_id === shipTypeId);
