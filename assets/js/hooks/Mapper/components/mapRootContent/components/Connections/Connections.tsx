import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import {
  ConnectionInfoOutput,
  ConnectionOutput,
  ConnectionType,
  MassState,
  OutCommand,
  Passage,
  PassageWithSourceTarget,
  SolarSystemConnection,
} from '@/hooks/Mapper/types';
import clsx from 'clsx';
import { Sidebar } from 'primereact/sidebar';
import { VirtualScroller, VirtualScrollerTemplateOptions } from 'primereact/virtualscroller';
import { useCallback, useEffect, useMemo, useState } from 'react';
import classes from './Connections.module.scss';

import { InfoDrawer, SystemView, TimeAgo } from '@/hooks/Mapper/components/ui-kit';
import { kgToTons } from '@/hooks/Mapper/utils/kgToTons.ts';
import { PassageCard } from './PassageCard';
import { PassageMassDialog } from './PassageMassDialog';
import { calculateMassBalance, MassBalanceStatus, reconcileMassRange } from './calculateMassBalance.ts';
import { calculatePolarizations, formatPolarizationRemaining } from './calculatePolarization.ts';
import { getMassAlerts } from './getMassAlerts.ts';

const sortByDate = (a: string, b: string) => new Date(a).getTime() - new Date(b).getTime();

const statusColor: Record<MassBalanceStatus, string> = {
  Stable: 'text-emerald-300',
  Reduced: 'text-yellow-300',
  Critical: 'text-red-400',
  Collapsed: 'text-stone-400',
};

const observedStatusName: Record<MassState, MassBalanceStatus> = {
  [MassState.normal]: 'Stable',
  [MassState.half]: 'Reduced',
  [MassState.verge]: 'Critical',
};

export interface ConnectionPassagesContentProps {
  passages: PassageWithSourceTarget[];
  onEditPassage: (passage: PassageWithSourceTarget) => void;
}

export const ConnectionPassages = ({ passages = [], onEditPassage }: ConnectionPassagesContentProps) => {
  const itemTemplate = useCallback(
    (item: PassageWithSourceTarget, options: VirtualScrollerTemplateOptions) => {
      return (
        <div
          className={clsx(classes.CharacterRow, 'w-full box-border', {
            'surface-hover': options.odd,
            ['border-b border-gray-600 border-opacity-20']: !options.last,
            ['bg-green-500 hover:bg-green-700 transition duration-300 bg-opacity-10 hover:bg-opacity-10']: false,
          })}
          style={{ height: options.props.itemSize + 'px' }}
        >
          <PassageCard {...item} onEdit={() => onEditPassage(item)} />
        </div>
      );
    },
    [onEditPassage],
  );

  if (passages.length === 0) {
    return <div className="flex justify-center items-center text-stone-400 select-none">Nobody passed here</div>;
  }

  return (
    <VirtualScroller
      items={passages}
      itemSize={43}
      itemTemplate={itemTemplate}
      className={clsx(
        classes.VirtualScroller,
        'w-full h-full overflow-x-hidden overflow-y-auto custom-scrollbar select-none',
      )}
      autoSize={false}
    />
  );
};

export interface OnTheMapProps {
  selectedConnection: SolarSystemConnection | null;
  onHide: () => void;
}

export const Connections = ({ selectedConnection, onHide }: OnTheMapProps) => {
  const {
    data: { connections, wormholesData },
    outCommand,
  } = useMapRootState();

  const cnInfo = useMemo(() => {
    if (!selectedConnection) {
      return null;
    }

    return connections.find(x => x.source === selectedConnection.source && x.target === selectedConnection.target);
  }, [connections, selectedConnection]);

  const isWormhole = useMemo(() => {
    return cnInfo?.type === ConnectionType.wormhole;
  }, [cnInfo]);

  const [passages, setPassages] = useState<Passage[]>([]);
  const [info, setInfo] = useState<ConnectionInfoOutput | null>(null);
  const [editingPassage, setEditingPassage] = useState<PassageWithSourceTarget | null>(null);
  const [massUpdateInFlight, setMassUpdateInFlight] = useState(false);
  const [observedMassStatusOverride, setObservedMassStatusOverride] = useState<MassState | null>(null);
  const [currentTime, setCurrentTime] = useState(Date.now());

  useEffect(() => {
    if (!selectedConnection) return;
    setCurrentTime(Date.now());
    const timer = window.setInterval(() => setCurrentTime(Date.now()), 1_000);
    return () => window.clearInterval(timer);
  }, [selectedConnection]);

  const loadInfo = useCallback(
    async (connection: SolarSystemConnection) => {
      const result = await outCommand<ConnectionInfoOutput>({
        type: OutCommand.getConnectionInfo,
        data: {
          from: connection.source,
          to: connection.target,
        },
      });

      setInfo(result);
    },
    [outCommand],
  );

  const loadPassages = useCallback(
    async (connection: SolarSystemConnection) => {
      const result = await outCommand<ConnectionOutput>({
        type: OutCommand.getPassages,
        data: {
          from: connection.source,
          to: connection.target,
        },
      });

      setPassages([...result.passages].sort((a, b) => sortByDate(b.inserted_at, a.inserted_at)));
    },
    [outCommand],
  );

  const preparedPassages = useMemo(() => {
    if (!cnInfo) {
      return [];
    }

    return [...passages]
      .sort((a, b) => sortByDate(b.inserted_at, a.inserted_at))
      .map<PassageWithSourceTarget>(x => ({
        ...x,
        source: x.from ? cnInfo.target : cnInfo.source,
        target: x.from ? cnInfo.source : cnInfo.target,
      }));
  }, [cnInfo, passages]);

  const polarizations = useMemo(() => calculatePolarizations(passages, currentTime), [currentTime, passages]);

  useEffect(() => {
    if (!selectedConnection) {
      setEditingPassage(null);
      setMassUpdateInFlight(false);
      setObservedMassStatusOverride(null);
      return;
    }

    setEditingPassage(null);
    setMassUpdateInFlight(false);
    setObservedMassStatusOverride(null);
    loadInfo(selectedConnection);
    loadPassages(selectedConnection);
  }, [loadInfo, loadPassages, selectedConnection]);

  const wormholeData = useMemo(() => {
    return info?.wormhole_type ? wormholesData[info.wormhole_type] : null;
  }, [info?.wormhole_type, wormholesData]);

  const wormholeNominalMass = useMemo(() => {
    return typeof wormholeData?.total_mass === 'number' && wormholeData.total_mass > 0 ? wormholeData.total_mass : null;
  }, [wormholeData]);

  const massBalance = useMemo(() => {
    const regenerationPerDay = Number(wormholeData?.mass_regen ?? 0);

    return calculateMassBalance(passages, wormholeNominalMass, {
      massRegenerationPerDay: Number.isFinite(regenerationPerDay) ? regenerationPerDay : 0,
      trackingStartedAt: info?.mass_tracking_started_at,
      now: new Date(currentTime),
    });
  }, [currentTime, info?.mass_tracking_started_at, passages, wormholeData?.mass_regen, wormholeNominalMass]);

  const massStatus = useMemo(() => {
    const { statusMinimum, statusMaximum } = massBalance;

    if (!statusMinimum || !statusMaximum) return null;
    return statusMinimum === statusMaximum ? statusMinimum : `${statusMinimum} - ${statusMaximum}`;
  }, [massBalance]);

  const effectiveObservedMassStatus = observedMassStatusOverride ?? cnInfo?.mass_status ?? MassState.normal;
  const observedStatus = observedStatusName[effectiveObservedMassStatus];
  const reconciledRange = useMemo(() => {
    return reconcileMassRange(massBalance, wormholeNominalMass, effectiveObservedMassStatus);
  }, [effectiveObservedMassStatus, massBalance, wormholeNominalMass]);

  const massAlerts = useMemo(
    () =>
      getMassAlerts(
        massBalance,
        Number(wormholeData?.max_mass_per_jump) || null,
        effectiveObservedMassStatus,
        reconciledRange,
      ),
    [effectiveObservedMassStatus, massBalance, reconciledRange, wormholeData?.max_mass_per_jump],
  );

  const unconfirmedPassages = useMemo(() => {
    return passages.filter(passage => passage.mass_confirmed_at == null).length;
  }, [passages]);

  const handleEditPassage = useCallback((passage: PassageWithSourceTarget) => {
    setEditingPassage(passage);
  }, []);

  const handleHidePassageDialog = useCallback(() => {
    setEditingPassage(null);
  }, []);

  const handleSavePassageMass = useCallback(
    async (mass: number, massStatus: MassState | null) => {
      if (!editingPassage) {
        return;
      }

      setMassUpdateInFlight(true);

      const updateRequest = outCommand({
        type: OutCommand.updatePassageMass,
        data: {
          id: editingPassage.id,
          mass,
          mass_status: massStatus,
        },
      });

      // Apply the passage locally before the observed status, matching the
      // server-side persistence order without waiting for signature broadcasts.
      const massConfirmedAt = new Date().toISOString();

      setPassages(prev =>
        prev.map(passage =>
          passage.id === editingPassage.id ? { ...passage, mass, mass_confirmed_at: massConfirmedAt } : passage,
        ),
      );

      if (massStatus != null) {
        setObservedMassStatusOverride(massStatus);
      }

      setEditingPassage(prev => (prev ? { ...prev, mass, mass_confirmed_at: massConfirmedAt } : prev));
      handleHidePassageDialog();

      try {
        await updateRequest;
      } catch {
        setObservedMassStatusOverride(null);
        if (selectedConnection) {
          await Promise.all([loadInfo(selectedConnection), loadPassages(selectedConnection)]);
        }
      } finally {
        setMassUpdateInFlight(false);
      }
    },
    [editingPassage, handleHidePassageDialog, loadInfo, loadPassages, outCommand, selectedConnection],
  );

  if (!cnInfo) {
    return null;
  }

  return (
    <Sidebar
      className={clsx(classes.SidebarOnTheMap, 'bg-neutral-900')}
      visible={!!selectedConnection}
      position="right"
      onHide={onHide}
      header="Connection Info"
      icons={<></>}
    >
      <div className={clsx(classes.SidebarContent, '')}>
        {/* Connection Info */}
        <div className="px-2 flex flex-col gap-2">
          {/* Connection Info Row */}
          <div className="flex justify-between gap-2">
            {/*Left column*/}
            <div>
              {isWormhole && info?.locked_at && (
                <InfoDrawer title="Save Mass">
                  <TimeAgo timestamp={info.locked_at} />
                  {info.locked_by_name && <span className="text-neutral-400"> by {info.locked_by_name}</span>}
                </InfoDrawer>
              )}
            </div>
            {/*Right column*/}
            <InfoDrawer title="Connection" rightSide>
              <div className="flex justify-end gap-2 items-center">
                <SystemView
                  showCustomName
                  systemId={cnInfo.source}
                  className={clsx(classes.InfoTextSize, 'select-none text-center')}
                  hideRegion
                />
                <span className="pi pi-angle-double-right text-stone-500 text-[15px]"></span>
                <SystemView
                  showCustomName
                  systemId={cnInfo.target}
                  className={clsx(classes.InfoTextSize, 'select-none text-center')}
                  hideRegion
                />
              </div>
            </InfoDrawer>
          </div>

          <div className="flex justify-between gap-2">
            {/*Left column*/}
            <div>
              {isWormhole && info?.marl_eol_time && (
                <InfoDrawer title="Mark EOL Time">
                  <TimeAgo timestamp={info.marl_eol_time} />
                </InfoDrawer>
              )}
            </div>

            {/*Right column*/}
            <div>
              {isWormhole && (
                <InfoDrawer title="Approximate mass of passages" rightSide>
                  {kgToTons(massBalance.trackedMass)}
                </InfoDrawer>
              )}
            </div>
          </div>

          <div className="flex gap-2"></div>

          {isWormhole && passages.length > 0 && (
            <div className="flex justify-end">
              <InfoDrawer title="Passage mass confirmations" rightSide>
                <span className={unconfirmedPassages > 0 ? 'text-amber-300' : 'text-emerald-300'}>
                  {unconfirmedPassages > 0 ? `${unconfirmedPassages} unconfirmed` : 'All confirmed'}
                </span>
              </InfoDrawer>
            </div>
          )}

          {isWormhole && info?.mass_tracking_started_at && (
            <div className="flex justify-end">
              <InfoDrawer title="Mass tracking since" rightSide>
                <TimeAgo timestamp={info.mass_tracking_started_at} />
              </InfoDrawer>
            </div>
          )}

          {isWormhole && (
            <div className="rounded border border-neutral-700/80 bg-neutral-950/40 p-3 text-xs">
              <div className="mb-3 flex items-center justify-between gap-3">
                <span className="font-medium text-stone-200">Wormhole mass balance</span>
                <span className="text-stone-400">
                  {info?.wormhole_type ?? 'Unknown type'}
                  {wormholeNominalMass && ` | ${kgToTons(wormholeNominalMass)} nominal`}
                </span>
              </div>

              <div className="grid grid-cols-2 gap-x-4 gap-y-2">
                <span className="text-stone-400">Confirmed passages</span>
                <span className="text-right text-emerald-300">{kgToTons(massBalance.confirmedMass)}</span>
                <span className="text-stone-400">Open estimate</span>
                <span className="text-right text-amber-300">{kgToTons(massBalance.estimatedOpenMass)}</span>
                <span className="text-stone-400">Tracked total</span>
                <span className="text-right text-stone-200">{kgToTons(massBalance.trackedMass)}</span>
                {massBalance.regeneratedMass > 0 && (
                  <>
                    <span className="text-stone-400">Regenerated mass</span>
                    <span className="text-right text-sky-300">+{kgToTons(massBalance.regeneratedMass)}</span>
                    <span className="text-stone-400">Effective depletion</span>
                    <span className="text-right text-stone-200">{kgToTons(massBalance.effectiveMass)}</span>
                  </>
                )}

                {massBalance.remainingMinimum != null && massBalance.remainingMaximum != null ? (
                  <>
                    <span className="text-stone-400">Remaining range</span>
                    <span className="text-right text-stone-200">
                      {kgToTons(massBalance.remainingMinimum)} - {kgToTons(massBalance.remainingMaximum)}
                    </span>
                    <span className="text-stone-400">Projected status</span>
                    <span
                      className={clsx(
                        'text-right',
                        massBalance.statusMinimum === massBalance.statusMaximum && massBalance.statusMinimum
                          ? statusColor[massBalance.statusMinimum]
                          : 'text-amber-300',
                      )}
                    >
                      {massStatus}
                    </span>
                    <span className="text-stone-400">Observed status</span>
                    <span className={clsx('text-right', statusColor[observedStatus])}>{observedStatus}</span>
                    {reconciledRange.compatible &&
                    reconciledRange.minimum != null &&
                    reconciledRange.maximum != null ? (
                      <>
                        <span className="text-stone-400">Constrained range</span>
                        <span className="text-right text-emerald-300">
                          {kgToTons(reconciledRange.minimum)} - {kgToTons(reconciledRange.maximum)}
                        </span>
                      </>
                    ) : null}
                    {massUpdateInFlight && (
                      <span className="col-span-2 text-right text-[11px] text-stone-500">Syncing with server...</span>
                    )}
                  </>
                ) : (
                  <>
                    <span className="col-span-2 mt-1 text-amber-300/90">
                      Set a known wormhole type to calculate remaining mass.
                    </span>
                  </>
                )}
              </div>

              {wormholeNominalMass && (
                <div className="mt-3 h-2 overflow-hidden rounded bg-neutral-800">
                  <div className="flex h-full">
                    <div
                      className="shrink-0 bg-emerald-500"
                      style={{
                        width: `${Math.min((massBalance.confirmedMass / wormholeNominalMass) * 100, 100)}%`,
                      }}
                    />
                    <div
                      className="shrink-0 bg-amber-500"
                      style={{
                        width: `${Math.min((massBalance.estimatedOpenMass / wormholeNominalMass) * 100, 100)}%`,
                      }}
                    />
                  </div>
                </div>
              )}

              {massAlerts.length > 0 && (
                <div className="mt-3 flex flex-col gap-1.5">
                  {massAlerts.map((alert, index) => (
                    <div
                      key={`${alert.level}-${index}`}
                      className={clsx('rounded border px-2 py-1.5', {
                        'border-sky-500/30 bg-sky-500/10 text-sky-300': alert.level === 'hint',
                        'border-amber-500/30 bg-amber-500/10 text-amber-300': alert.level === 'warning',
                        'border-red-500/30 bg-red-500/10 text-red-300': alert.level === 'danger',
                      })}
                    >
                      <span
                        className={clsx(
                          'pi mr-1.5',
                          alert.level === 'hint' ? 'pi-info-circle' : 'pi-exclamation-triangle',
                        )}
                      />
                      {alert.text}
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {isWormhole && polarizations.length > 0 && (
            <div className="rounded border border-neutral-700/80 bg-neutral-950/40 p-3 text-xs">
              <div className="mb-2 font-medium text-stone-200">Polarization</div>
              <div className="flex flex-col gap-1.5">
                {polarizations.map(polarization => (
                  <div key={polarization.characterId} className="flex items-center justify-between gap-3">
                    <span className="truncate text-stone-300">{polarization.characterName}</span>
                    <span className={polarization.state === 'polarized' ? 'text-red-400' : 'text-amber-300'}>
                      {polarization.state === 'polarized' ? 'Polarized' : 'Directional timer'} ·{' '}
                      {formatPolarizationRemaining(polarization.expiresAt, currentTime)}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* separator */}
        <div className="w-full h-px bg-neutral-800 px-0.5"></div>

        <ConnectionPassages passages={preparedPassages} onEditPassage={handleEditPassage} />
      </div>

      <PassageMassDialog
        passage={editingPassage}
        visible={editingPassage != null}
        onHide={handleHidePassageDialog}
        onSave={handleSavePassageMass}
      />
    </Sidebar>
  );
};
