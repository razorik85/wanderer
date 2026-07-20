import { WdButton, WdTooltipWrapper } from '@/hooks/Mapper/components/ui-kit';
import { MassState, OutCommand, Passage } from '@/hooks/Mapper/types';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
import clsx from 'clsx';
import { useEffect, useMemo, useState } from 'react';
import { TimeAgo } from '@/hooks/Mapper/components/ui-kit';
import { getShipName } from './PassageCard/getShipName.ts';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import { getShipMassTemplates } from './massTemplates.ts';
import { ShipMassTemplate } from '@/hooks/Mapper/types/options.ts';

type PassageMassDialogProps = {
  passage: Passage | null;
  visible: boolean;
  allowConnectionClosed: boolean;
  onHide: () => void;
  onSave: (mass: number, massStatus: MassState | null, connectionClosed: boolean) => Promise<void> | void;
};

type ObservedStatus = MassState | 'closed' | null;

const KG_PER_TON = 1000;

const getPassageMassTons = (passage: Passage) => {
  const massKg = passage.mass ?? parseInt(passage.ship.ship_type_info.mass);
  return Math.round(massKg / KG_PER_TON);
};

const parseMassValue = (value: string) => {
  const sanitized = value.replace(/[^\d]/g, '');

  if (sanitized === '') {
    return null;
  }

  const parsed = parseInt(sanitized);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
};

export const PassageMassDialog = ({
  passage,
  visible,
  allowConnectionClosed,
  onHide,
  onSave,
}: PassageMassDialogProps) => {
  const { outCommand } = useMapRootState();
  const [massValue, setMassValue] = useState('');
  const [saving, setSaving] = useState(false);
  const [observedStatus, setObservedStatus] = useState<ObservedStatus>(null);
  const [massTemplates, setMassTemplates] = useState<ShipMassTemplate[]>([]);

  useEffect(() => {
    if (!passage) {
      setMassValue('');
      setMassStatus(null);
      return;
    }

    setMassValue(`${getPassageMassTons(passage)}`);
    setObservedStatus(null);
  }, [passage]);

  useEffect(() => {
    if (!visible) return;

    outCommand<{ user_settings?: { mass_templates?: ShipMassTemplate[] } }>({
      type: OutCommand.getUserSettings,
      data: null,
    })
      .then(response => setMassTemplates(response.user_settings?.mass_templates ?? []))
      .catch(() => setMassTemplates([]));
  }, [outCommand, visible]);

  const parsedMass = useMemo(() => parseMassValue(massValue), [massValue]);
  const matchingTemplates = useMemo(
    () => (passage ? getShipMassTemplates(massTemplates, passage.ship.ship_type_id) : []),
    [massTemplates, passage],
  );

  const handleSave = async () => {
    if (!passage || parsedMass == null) {
      return;
    }

    setSaving(true);

    try {
      await onSave(
        parsedMass * KG_PER_TON,
        typeof observedStatus === 'number' ? observedStatus : null,
        observedStatus === 'closed',
      );
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog
      header="Edit passage mass"
      visible={visible}
      draggable
      resizable={false}
      style={{ width: '420px' }}
      onHide={onHide}
    >
      {passage && (
        <div className="flex flex-col gap-4">
          <div className="rounded border border-stone-700/80 bg-stone-900/70 p-3">
            <div className="grid grid-cols-[34px_1fr_auto] gap-3 items-start">
              <div
                className="w-[34px] h-[34px] rounded-[3px] border border-stone-700 bg-center bg-cover bg-no-repeat"
                style={{ backgroundImage: `url(https://images.evetech.net/types/${passage.ship.ship_type_id}/icon)` }}
              />

              <div className="min-w-0">
                <div className="text-sm text-stone-100 truncate">{passage.ship.ship_type_info.name}</div>
                {passage.ship.ship_name && (
                  <div className="text-xs text-stone-400 truncate">{getShipName(passage.ship.ship_name)}</div>
                )}
                <div className="mt-2 flex items-center gap-2 text-xs text-stone-400">
                  <span>{passage.character.name}</span>
                  <span className="text-stone-600">|</span>
                  <WdTooltipWrapper content={new Date(passage.inserted_at).toLocaleString()}>
                    <span className="cursor-default">
                      <TimeAgo timestamp={passage.inserted_at} />
                    </span>
                  </WdTooltipWrapper>
                </div>
              </div>

              <div
                className={clsx(
                  'w-[34px] h-[34px] rounded-[3px] border border-stone-700 bg-center bg-cover bg-no-repeat',
                  'justify-self-end',
                )}
                style={{
                  backgroundImage: `url(https://images.evetech.net/characters/${passage.character.eve_id}/portrait)`,
                }}
              />
            </div>
          </div>

          <div className="flex flex-col gap-2">
            <div
              className={clsx('rounded border px-3 py-2 text-xs', {
                'border-amber-500/40 bg-amber-500/10 text-amber-300': passage.mass_confirmed_at == null,
                'border-emerald-500/40 bg-emerald-500/10 text-emerald-300': passage.mass_confirmed_at != null,
              })}
            >
              {passage.mass_confirmed_at == null
                ? 'This passage mass is not confirmed yet.'
                : `Confirmed ${new Date(passage.mass_confirmed_at).toLocaleString()}`}
            </div>

            <label className="text-sm text-stone-300" htmlFor="passage-mass">
              Passage mass in tonnes
            </label>

            {matchingTemplates.length > 0 && (
              <div className="flex flex-wrap gap-2">
                {matchingTemplates.map(template => (
                  <button
                    key={`${template.ship_type_id}-${template.label}-${template.mass_tons}`}
                    type="button"
                    onClick={() => setMassValue(String(template.mass_tons))}
                    className={clsx(
                      'rounded border px-2.5 py-1.5 text-xs transition-colors',
                      parsedMass === template.mass_tons
                        ? 'border-sky-400 bg-sky-500/20 text-sky-200'
                        : 'border-stone-600 bg-stone-800 text-stone-300 hover:border-stone-500 hover:bg-stone-700',
                    )}
                  >
                    {template.label} · {new Intl.NumberFormat().format(template.mass_tons)} t
                  </button>
                ))}
              </div>
            )}

            <InputText
              id="passage-mass"
              value={massValue}
              onChange={event => setMassValue(event.target.value.replace(/[^\d]/g, ''))}
              placeholder="Mass in tonnes"
              className="w-full"
            />

            <div className="text-xs text-stone-500">
              {parsedMass == null
                ? 'Enter whole tonnes'
                : `Stored as ${new Intl.NumberFormat().format(parsedMass * KG_PER_TON)} kg`}
            </div>
          </div>

          <div className="flex flex-col gap-2">
            <label className="text-sm text-stone-300" htmlFor="passage-mass-status">
              Observed wormhole status
            </label>
            <select
              id="passage-mass-status"
              value={observedStatus ?? ''}
              onChange={event =>
                setObservedStatus(
                  event.target.value === ''
                    ? null
                    : event.target.value === 'closed'
                      ? 'closed'
                      : (Number(event.target.value) as MassState),
                )
              }
              className="h-10 rounded border border-stone-700 bg-stone-900 px-3 text-sm text-stone-200"
            >
              <option value="">Unchanged</option>
              <option value={MassState.normal}>Stable</option>
              <option value={MassState.half}>Reduced</option>
              <option value={MassState.verge}>Critical</option>
              {allowConnectionClosed && <option value="closed">Closed</option>}
            </select>
            <div className="text-xs text-stone-500">
              {allowConnectionClosed
                ? 'Select Closed only when this passage collapsed the wormhole. The connection will be removed.'
                : 'Only the latest passage can be marked as collapsed.'}
            </div>
          </div>

          <div className="flex justify-end gap-2">
            <WdButton outlined size="small" label="Cancel" onClick={onHide} />
            <WdButton
              outlined
              size="small"
              label={saving ? 'Saving...' : 'Save'}
              onClick={handleSave}
              disabled={parsedMass == null || saving}
            />
          </div>
        </div>
      )}
    </Dialog>
  );
};
