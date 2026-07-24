import { SignatureGroup, SignatureKind, SystemSignature } from '@/hooks/Mapper/types';
import { getSignatureCounts } from './SignatureCounts';

const signature = (eveId: string, group: SignatureGroup, deleted = false): SystemSignature => ({
  eve_id: eveId,
  group,
  deleted,
  kind: SignatureKind.CosmicSignature,
  name: '',
  type: '',
});

describe('getSignatureCounts', () => {
  it('groups active signatures and omits empty groups', () => {
    expect(
      getSignatureCounts([
        signature('AAA-001', SignatureGroup.GasSite),
        signature('AAA-002', SignatureGroup.GasSite),
        signature('AAA-003', SignatureGroup.RelicSite),
        signature('AAA-004', SignatureGroup.DataSite, true),
      ]),
    ).toEqual([
      { group: SignatureGroup.GasSite, count: 2 },
      { group: SignatureGroup.RelicSite, count: 1 },
    ]);
  });

  it('only returns enabled signature groups', () => {
    expect(
      getSignatureCounts(
        [
          signature('AAA-001', SignatureGroup.Wormhole),
          signature('AAA-002', SignatureGroup.RelicSite),
          signature('AAA-003', SignatureGroup.DataSite),
        ],
        [SignatureGroup.RelicSite],
      ),
    ).toEqual([{ group: SignatureGroup.RelicSite, count: 1 }]);
  });
});
