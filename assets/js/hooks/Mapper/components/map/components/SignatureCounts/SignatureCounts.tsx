import { useMemo } from 'react';
import {
  getGroupIdByRawGroup,
  GROUPS,
  GROUPS_LIST,
} from '@/hooks/Mapper/components/mapInterface/widgets/SystemSignatures/constants.ts';
import { SignatureGroup, SystemSignature } from '@/hooks/Mapper/types';
import { TooltipPosition, WdTooltipWrapper } from '@/hooks/Mapper/components/ui-kit';

type SignatureCountsProps = {
  signatures: SystemSignature[];
};

export const getSignatureCounts = (signatures: SystemSignature[]) => {
  const counts = new Map<SignatureGroup, number>();

  signatures.forEach(signature => {
    const group = getGroupIdByRawGroup(signature.group);
    if (signature.deleted || !group || !GROUPS_LIST.includes(group)) return;
    counts.set(group, (counts.get(group) ?? 0) + 1);
  });

  return GROUPS_LIST.flatMap(group => {
    const count = counts.get(group) ?? 0;
    return count > 0 ? [{ group, count }] : [];
  });
};

export const SignatureCounts = ({ signatures }: SignatureCountsProps) => {
  const counts = useMemo(() => getSignatureCounts(signatures), [signatures]);

  if (counts.length === 0) return null;

  return (
    <div className="flex items-center justify-center gap-1 rounded bg-neutral-950/90 border border-neutral-700 px-1 py-0.5 shadow-md">
      {counts.map(({ group, count }) => {
        const groupInfo = GROUPS[group];

        return (
          <WdTooltipWrapper key={group} content={`${group}: ${count}`} position={TooltipPosition.bottom}>
            <span className="flex items-center gap-0.5 text-[9px] leading-none text-stone-100">
              <img
                src={groupInfo.icon}
                width={groupInfo.w}
                height={groupInfo.h}
                alt=""
                className="max-w-[12px] max-h-[12px]"
              />
              <span>{count}</span>
            </span>
          </WdTooltipWrapper>
        );
      })}
    </div>
  );
};
