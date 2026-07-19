import { WdButton } from '@/hooks/Mapper/components/ui-kit';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import { OutCommand } from '@/hooks/Mapper/types';
import { ShipMassTemplate } from '@/hooks/Mapper/types/options.ts';
import { InputText } from 'primereact/inputtext';
import { useEffect, useMemo, useState } from 'react';

type ShipSearchResult = {
  ship_type_id: number;
  ship_type_name: string;
  base_mass_tons: number;
};

const onlyDigits = (value: string) => value.replace(/[^\d]/g, '');

export const MassTemplatesSettings = () => {
  const {
    data: { options },
    outCommand,
    update,
  } = useMapRootState();
  const [templates, setTemplates] = useState<ShipMassTemplate[]>(options.mass_templates ?? []);
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<ShipSearchResult[]>([]);
  const [selectedShip, setSelectedShip] = useState<ShipSearchResult | null>(null);
  const [label, setLabel] = useState('');
  const [massTons, setMassTons] = useState('');
  const [searching, setSearching] = useState(false);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => setTemplates(options.mass_templates ?? []), [options.mass_templates]);

  const canAdd = selectedShip != null && label.trim() !== '' && Number(massTons) > 0;
  const groupedTemplates = useMemo(() => {
    return templates.reduce<Record<string, ShipMassTemplate[]>>((groups, template) => {
      const key = `${template.ship_type_id}:${template.ship_type_name}`;
      groups[key] = [...(groups[key] ?? []), template];
      return groups;
    }, {});
  }, [templates]);

  const search = async () => {
    if (query.trim().length < 2) return;
    setSearching(true);
    try {
      const response = await outCommand<{ ships: ShipSearchResult[] }>({
        type: OutCommand.searchShipTypes,
        data: { query: query.trim() },
      });
      setResults(response.ships ?? []);
    } finally {
      setSearching(false);
    }
  };

  const selectShip = (ship: ShipSearchResult) => {
    setSelectedShip(ship);
    setQuery(ship.ship_type_name);
    setMassTons(String(ship.base_mass_tons));
    setResults([]);
  };

  const addTemplate = () => {
    if (!selectedShip || !canAdd) return;
    setTemplates(current => [
      ...current,
      {
        ship_type_id: selectedShip.ship_type_id,
        ship_type_name: selectedShip.ship_type_name,
        label: label.trim(),
        mass_tons: Number(massTons),
      },
    ]);
    setLabel('');
    setMessage(null);
  };

  const removeTemplate = (templateToRemove: ShipMassTemplate) => {
    setTemplates(current => current.filter(template => template !== templateToRemove));
    setMessage(null);
  };

  const save = async () => {
    setSaving(true);
    setMessage(null);
    try {
      const response = await outCommand<{ success: boolean; templates?: ShipMassTemplate[]; error?: string }>({
        type: OutCommand.updateMassTemplates,
        data: { templates },
      });

      if (!response.success || !response.templates) {
        setMessage(response.error ?? 'Could not save mass presets.');
        return;
      }

      setTemplates(response.templates);
      update({ options: { ...options, mass_templates: response.templates } });
      setMessage('Mass presets saved for this map.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="flex h-full flex-col gap-3 overflow-y-auto pr-2 custom-scrollbar">
      <div>
        <div className="text-sm font-medium text-stone-200">Shared ship mass presets</div>
        <div className="mt-1 text-xs text-stone-500">
          Add freely named fit or propulsion states. Values are entered in whole tonnes and shared with everyone on this
          map.
        </div>
      </div>

      <div className="rounded border border-stone-700 bg-stone-900/60 p-3">
        <div className="flex gap-2">
          <InputText
            value={query}
            onChange={event => {
              setQuery(event.target.value);
              setSelectedShip(null);
            }}
            onKeyDown={event => event.key === 'Enter' && search()}
            placeholder="Search ship, e.g. Praxis"
            className="min-w-0 flex-1"
          />
          <WdButton outlined size="small" label={searching ? 'Searching...' : 'Search'} onClick={search} />
        </div>

        {results.length > 0 && (
          <div className="mt-2 max-h-32 overflow-y-auto rounded border border-stone-700 bg-stone-950 custom-scrollbar">
            {results.map(ship => (
              <button
                key={ship.ship_type_id}
                type="button"
                onClick={() => selectShip(ship)}
                className="flex w-full items-center justify-between border-b border-stone-800 px-3 py-2 text-left text-xs text-stone-300 last:border-0 hover:bg-stone-800"
              >
                <span>{ship.ship_type_name}</span>
                <span className="text-stone-500">Base {new Intl.NumberFormat().format(ship.base_mass_tons)} t</span>
              </button>
            ))}
          </div>
        )}

        {selectedShip && (
          <div className="mt-3 grid grid-cols-[1fr_1fr_auto] gap-2">
            <InputText value={label} onChange={event => setLabel(event.target.value)} placeholder="Label, e.g. Hot" />
            <InputText
              value={massTons}
              onChange={event => setMassTons(onlyDigits(event.target.value))}
              placeholder="Mass in tonnes"
            />
            <WdButton outlined size="small" label="Add" disabled={!canAdd} onClick={addTemplate} />
          </div>
        )}
      </div>

      <div className="flex flex-col gap-2">
        {Object.entries(groupedTemplates).map(([key, shipTemplates]) => (
          <div key={key} className="rounded border border-stone-700/80 bg-stone-900/40 p-3">
            <div className="mb-2 text-sm text-stone-200">{shipTemplates[0].ship_type_name}</div>
            <div className="flex flex-col gap-1.5">
              {shipTemplates.map((template, index) => (
                <div
                  key={`${template.label}-${template.mass_tons}-${index}`}
                  className="flex items-center justify-between gap-3 text-xs"
                >
                  <span className="text-stone-300">
                    {template.label} · {new Intl.NumberFormat().format(template.mass_tons)} t
                  </span>
                  <button
                    type="button"
                    onClick={() => removeTemplate(template)}
                    className="pi pi-trash text-stone-500 hover:text-red-400"
                    aria-label={`Delete ${template.label}`}
                  />
                </div>
              ))}
            </div>
          </div>
        ))}
        {templates.length === 0 && (
          <div className="py-4 text-center text-xs text-stone-500">No presets configured.</div>
        )}
      </div>

      <div className="mt-auto flex items-center justify-between gap-3 border-t border-stone-700 pt-3">
        <span className="text-xs text-stone-400">{message}</span>
        <WdButton
          outlined
          size="small"
          label={saving ? 'Saving...' : 'Save presets'}
          disabled={saving}
          onClick={save}
        />
      </div>
    </div>
  );
};
