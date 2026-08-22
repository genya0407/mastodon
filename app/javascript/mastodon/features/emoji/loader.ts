<<<<<<< HEAD
import { flattenEmojiData } from 'emojibase';
import type { CompactEmoji, FlatCompactEmoji, Locale } from 'emojibase';
=======
import { joinShortcodes } from 'emojibase';
import type { CompactEmoji, Locale, ShortcodesDataset } from 'emojibase';

import { onceAsyncByArgs } from '@/mastodon/utils/promises';
>>>>>>> origin/trunk

import {
  putEmojiData,
  putCustomEmojiData,
  putCacheValue,
  putLegacyShortcodes,
  loadCacheValue,
} from './database';
<<<<<<< HEAD
import { toSupportedLocale, toSupportedLocaleOrCustom } from './locale';
import type { CustomEmojiData } from './types';

export async function importEmojiData(localeString: string, path?: string) {
  const locale = toSupportedLocale(localeString);

  // Validate the provided path.
  if (path && !/^[/a-z]*\/packs\/assets\/compact-\w+\.json$/.test(path)) {
    throw new Error('Invalid path for emoji data');
  } else {
    // Otherwise get the path if not provided.
    path ??= await localeToPath(locale);
  }

  // Fix from #37858. Check if we've loaded this path before.
  const existing = await loadLatestEtag(locale);
  if (existing === path) {
    return null;
  }

  const emojis = await fetchAndCheckEtag<CompactEmoji[]>(locale, path);
=======
import { toSupportedLocale, toValidCacheKey } from './locale';
import type { CustomEmojiData } from './types';
import { emojiLogger } from './utils';

const log = emojiLogger('loader');

export async function importEmojiData(localeString: string, shortcodes = true) {
  const locale = toSupportedLocale(localeString);

  return importEmojiDataOnce(locale, shortcodes);
}

const importEmojiDataOnce = onceAsyncByArgs(importEmojiDataImpl);

async function importEmojiDataImpl(locale: Locale, shortcodes: boolean) {
  log(
    'importing emoji data for locale %s%s',
    locale,
    shortcodes ? ' and shortcodes' : '',
  );

  let emojis = await fetchIfNotLoaded<CompactEmoji[]>({
    key: locale,
    path: localeToEmojiPath(locale),
  });
>>>>>>> origin/trunk
  if (!emojis) {
    return;
  }

<<<<<<< HEAD
  await putLatestEtag(path, locale); // Fix from #37858. Put the path as the ETag to ensure we don't load the same data again.

  const flattenedEmojis: FlatCompactEmoji[] = flattenEmojiData(emojis);
  await putEmojiData(flattenedEmojis, locale);
  return flattenedEmojis;
}

export async function importCustomEmojiData() {
  const emojis = await fetchAndCheckEtag<CustomEmojiData[]>(
    'custom',
    '/api/v1/custom_emojis',
  );
  if (!emojis) {
    return;
  }
  await putCustomEmojiData(emojis);
  return emojis;
}

const modules = import.meta.glob<string>(
  '../../../../../node_modules/emojibase-data/**/compact.json',
  {
    query: '?url',
    import: 'default',
  },
);

export function localeToPath(locale: Locale) {
  const key = `../../../../../node_modules/emojibase-data/${locale}/compact.json`;
  if (!modules[key] || typeof modules[key] !== 'function') {
    throw new Error(`Unsupported locale: ${locale}`);
  }
  return modules[key]();
}

export async function fetchAndCheckEtag<ResultType extends object[]>(
  localeString: string,
  path: string,
): Promise<ResultType | null> {
  const locale = toSupportedLocaleOrCustom(localeString);

  // Use location.origin as this script may be loaded from a CDN domain.
  const url = new URL(path, location.origin);

  const oldEtag = await loadLatestEtag(locale);
  const response = await fetch(url, {
    headers: {
      'Content-Type': 'application/json',
      'If-None-Match': oldEtag ?? '', // Send the old ETag to check for modifications
    },
  });
  // If not modified, return null
  if (response.status === 304) {
    return null;
  }
  if (!response.ok) {
    throw new Error(
      `Failed to fetch emoji data for ${locale}: ${response.statusText}`,
    );
  }

  const data = (await response.json()) as ResultType;
  if (!Array.isArray(data)) {
    throw new Error(`Unexpected data format for ${locale}: expected an array`);
  }

  // Store the ETag for future requests
  const etag = response.headers.get('ETag');
  if (etag) {
    await putLatestEtag(etag, localeString);
=======
  const shortcodesData: ShortcodesDataset[] = [];
  if (shortcodes) {
    const shortcodesResponse = await fetchIfNotLoaded<ShortcodesDataset>({
      key: `${locale}-shortcodes`,
      path: localeToShortcodesPath(locale),
    });
    if (shortcodesResponse) {
      shortcodesData.push(shortcodesResponse);
    } else {
      throw new Error(`No shortcodes data found for locale ${locale}`);
    }
  }

  emojis = joinShortcodes(emojis, shortcodesData);

  await putEmojiData(emojis, locale);
  return emojis;
}

export async function importCustomEmojiData() {
  const response = await fetchAndCheckEtag({
    oldEtag: await loadCacheValue('custom'),
    path: '/api/v1/custom_emojis',
  });

  if (!response) {
    return;
  }

  const etag = response.headers.get('ETag');
  if (etag) {
    log('Custom emoji data fetched successfully, storing etag %s', etag);
    await putCacheValue('custom', etag);
  } else {
    log('No etag found in response for custom emoji data');
>>>>>>> origin/trunk
  }

  const emojis = (await response.json()) as CustomEmojiData[];
  await putCustomEmojiData({ emojis, clear: true });
  return emojis;
}

export async function importLegacyShortcodes() {
  const globPaths = import.meta.glob<string>(
    // We use import.meta.glob to eagerly load the URL, as the regular import() doesn't work inside the Web Worker.
    '../../../../../node_modules/emojibase-data/en/shortcodes/iamcal.json',
    { eager: true, import: 'default', query: '?url' },
  );
  const path = Object.values(globPaths)[0];
  if (!path) {
    throw new Error('IAMCAL shortcodes path not found');
  }
  const shortcodesData = await fetchIfNotLoaded<ShortcodesDataset>({
    key: 'shortcodes',
    path,
  });
  if (!shortcodesData) {
    return;
  }
  await putLegacyShortcodes(shortcodesData);
  return Object.keys(shortcodesData);
}

function localeToEmojiPath(locale: Locale) {
  const key = `../../../../../node_modules/emojibase-data/${locale}/compact.json`;
  const emojiModules = import.meta.glob<string>(
    '../../../../../node_modules/emojibase-data/**/compact.json',
    {
      query: '?url',
      import: 'default',
      eager: true,
    },
  );
  const path = emojiModules[key];
  if (!path) {
    throw new Error(`Unsupported locale: ${locale}`);
  }
  return path;
}

function localeToShortcodesPath(locale: Locale) {
  const key = `../../../../../node_modules/emojibase-data/${locale}/shortcodes/cldr.json`;
  const shortcodesModules = import.meta.glob<string>(
    '../../../../../node_modules/emojibase-data/**/shortcodes/cldr.json',
    {
      query: '?url',
      import: 'default',
      eager: true,
    },
  );
  const path = shortcodesModules[key];
  if (!path) {
    throw new Error(`Unsupported locale for shortcodes: ${locale}`);
  }
  return path;
}

async function fetchIfNotLoaded<ResultType extends object[] | object>({
  key: rawKey,
  path,
}: {
  key: string;
  path: string;
}): Promise<ResultType | null> {
  const key = toValidCacheKey(rawKey);

  const value = await loadCacheValue(key);

  if (value === path) {
    log('data for %s already loaded, skipping fetch', key);
    return null;
  }

  const response = await fetchAndCheckEtag({ path });
  if (!response) {
    return null;
  }

  log('data for %s fetched successfully, storing etag', key);
  await putCacheValue(key, path);

  return (await response.json()) as ResultType;
}

async function fetchAndCheckEtag({
  oldEtag,
  path,
}: {
  oldEtag?: string;
  path: string;
}) {
  const headers = new Headers({
    'Content-Type': 'application/json',
  });
  if (oldEtag) {
    headers.set('If-None-Match', oldEtag);
  }

  // Use location.origin as this script may be loaded from a CDN domain.
  const url = new URL(path, location.origin);
  const response = await fetch(url, { headers });

  // If not modified, return null
  if (response.status === 304) {
    log('etag not modified for %s', path);
    return null;
  }

  if (!response.ok) {
    throw new Error(
      `Failed to fetch emoji data for ${path}: ${response.statusText}`,
    );
  }

  return response;
}
