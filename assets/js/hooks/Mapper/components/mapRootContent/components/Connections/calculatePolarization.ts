import { Passage } from '@/hooks/Mapper/types';

export const POLARIZATION_DURATION_MS = 5 * 60 * 1000;
export const ACTIVE_PASSAGE_HISTORY_MS = 15 * 60 * 1000;

export type CharacterPolarization = {
  characterId: string;
  characterName: string;
  state: 'partial' | 'polarized';
  expiresAt: number;
};

export const calculatePolarizations = (passages: Passage[], now = Date.now()): CharacterPolarization[] => {
  const byCharacter = new Map<string, Passage[]>();

  passages.forEach(passage => {
    const characterId = String(passage.character.eve_id);
    byCharacter.set(characterId, [...(byCharacter.get(characterId) ?? []), passage]);
  });

  return [...byCharacter.entries()]
    .map(([characterId, characterPassages]) => {
      const ordered = [...characterPassages].sort(
        (a, b) => new Date(b.inserted_at).getTime() - new Date(a.inserted_at).getTime(),
      );
      const latest = ordered[0];
      const latestByDirection = new Map<boolean, Passage>();

      ordered.forEach(passage => {
        if (!latestByDirection.has(passage.from)) latestByDirection.set(passage.from, passage);
      });

      const activeDirections = [...latestByDirection.values()]
        .map(passage => new Date(passage.inserted_at).getTime() + POLARIZATION_DURATION_MS)
        .filter(expiresAt => expiresAt > now);

      if (activeDirections.length === 0) return null;

      // After the latest jump the next possible traversal is in the opposite
      // direction. A still-running timer for that direction blocks the jump.
      const nextDirectionPassage = latestByDirection.get(!latest.from);
      const nextDirectionExpiry = nextDirectionPassage
        ? new Date(nextDirectionPassage.inserted_at).getTime() + POLARIZATION_DURATION_MS
        : null;
      const isPolarized = nextDirectionExpiry != null && nextDirectionExpiry > now;

      return {
        characterId,
        characterName: latest.character.name,
        state: isPolarized ? 'polarized' : 'partial',
        expiresAt: isPolarized ? nextDirectionExpiry : Math.max(...activeDirections),
      } satisfies CharacterPolarization;
    })
    .filter((entry): entry is CharacterPolarization => entry != null)
    .sort((a, b) => (a.state === b.state ? a.expiresAt - b.expiresAt : a.state === 'polarized' ? -1 : 1));
};

export const isRecentPassage = (passage: Passage, now = Date.now()) =>
  new Date(passage.inserted_at).getTime() >= now - ACTIVE_PASSAGE_HISTORY_MS;

export const formatPolarizationRemaining = (expiresAt: number, now = Date.now()) => {
  const seconds = Math.max(Math.ceil((expiresAt - now) / 1000), 0);
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
};
