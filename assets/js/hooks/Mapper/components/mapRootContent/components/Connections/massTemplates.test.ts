import { getShipMassTemplates } from './massTemplates.ts';

describe('getShipMassTemplates', () => {
  it('returns only presets for the passage ship type', () => {
    const result = getShipMassTemplates(
      [
        { ship_type_id: 47466, ship_type_name: 'Praxis', label: 'Cold', mass_tons: 191_000 },
        { ship_type_id: 47466, ship_type_name: 'Praxis', label: 'Hot', mass_tons: 219_000 },
        { ship_type_id: 12017, ship_type_name: 'Devoter', label: 'Cold', mass_tons: 118_000 },
      ],
      47466,
    );

    expect(result.map(template => template.label)).toEqual(['Cold', 'Hot']);
  });
});
