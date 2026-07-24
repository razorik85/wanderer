import { sortOnlineFunc } from '@/hooks/Mapper/components/hooks/useGetOwnOnlineCharacters.ts';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import { WithChildren } from '@/hooks/Mapper/types/common.ts';
import clsx from 'clsx';
import { useMemo } from 'react';
import { Characters } from '../characters/Characters';
import { InputSwitch } from 'primereact/inputswitch';
import { useMapSettings } from '@/hooks/Mapper/components/mapRootContent/components/MapSettings/MapSettingsProvider.tsx';
import { UserSettingsRemoteProps } from '@/hooks/Mapper/components/mapRootContent/components/MapSettings/types.ts';
import { TooltipPosition, WdTooltipWrapper } from '@/hooks/Mapper/components/ui-kit';

const Topbar = ({ children }: WithChildren) => {
  const {
    data: { characters, userCharacters },
  } = useMapRootState();
  const { settings, updateSetting, isRemoteReady } = useMapSettings();

  const charsToShow = useMemo(() => {
    return characters.filter(x => userCharacters.includes(x.eve_id)).sort(sortOnlineFunc);
  }, [characters, userCharacters]);

  return (
    <nav
      className={clsx(
        'px-2 flex items-center justify-center min-w-0 h-12 pointer-events-auto',
        'border-b border-stone-800 bg-gray-800 bg-opacity-5',
        'bg-opacity-70 bg-neutral-900',
      )}
    >
      <span className="flex-1"></span>
      <span className="mr-2"></span>
      <div className="flex flex-col gap-0.5 items-end">
        <Characters data={charsToShow} />
        <WdTooltipWrapper
          position={TooltipPosition.bottom}
          content={settings.mass_tracking_enabled ? 'Disable mass dialog popups' : 'Enable mass dialog popups'}
        >
          <label className="flex items-center gap-1 text-[10px] leading-none text-stone-300 cursor-pointer select-none">
            <span>Mass tracking</span>
            <InputSwitch
              checked={settings.mass_tracking_enabled}
              disabled={!isRemoteReady}
              onChange={event =>
                updateSetting(UserSettingsRemoteProps.mass_tracking_enabled, Boolean(event.value))
              }
              className="scale-[0.58] origin-right -my-1 -ml-2"
            />
          </label>
        </WdTooltipWrapper>
      </div>

      {children}
    </nav>
  );
};

// eslint-disable-next-line react/display-name
export default Topbar;
