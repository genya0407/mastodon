import { initialState } from '@/mastodon/initial_state';

import { EMOJI_DB_RELOAD_EVENT } from './constants';
import { toSupportedLocale } from './locale';
<<<<<<< HEAD
import type { LocaleOrCustom } from './types';
=======
import type { EmojiWorkerMessage } from './types';
>>>>>>> origin/trunk
import { emojiLogger } from './utils';

const userLocale = toSupportedLocale(initialState?.meta.locale ?? 'en');

let worker: Worker | null = null;

const log = emojiLogger('index');
const workerLog = emojiLogger('worker');

// This is too short, but better to fallback quickly than wait.
const WORKER_TIMEOUT = 2_000;

// Handle reload events
window.addEventListener(
  EMOJI_DB_RELOAD_EVENT,
  () => void handleEmojiDbReload(),
);

export async function initializeEmoji() {
  log('initializing emojis');

  // Create a temp worker, and assign it to the module-level worker once we know it's ready.
  let tempWorker: Worker | null = null;
  if (!worker && 'Worker' in window) {
    try {
      const { default: EmojiWorker } = await import('./worker?worker&inline');
      tempWorker = new EmojiWorker();
    } catch (err) {
      console.warn('Error creating web worker:', err);
    }
  }

<<<<<<< HEAD
  if (worker) {
    const timeoutId = setTimeout(() => {
      log('worker is not ready after timeout');
      worker = null;
      void fallbackLoad();
    }, WORKER_TIMEOUT);
    worker.addEventListener('message', (event: MessageEvent<string>) => {
      const { data: message } = event;
      if (message === 'ready') {
        log('worker ready, loading data');
        clearTimeout(timeoutId);
        messageWorker('custom');
        void loadEmojiLocale(userLocale);
        // Load English locale as well, because people are still used to
        // using it from before we supported other locales.
        if (userLocale !== 'en') {
          void loadEmojiLocale('en');
        }
      } else {
        log('got worker message: %s', message);
      }
    });
  } else {
=======
  if (!tempWorker) {
>>>>>>> origin/trunk
    void fallbackLoad();
    return;
  }

  const timeoutId = setTimeout(() => {
    log('worker is not ready after timeout');
    void fallbackLoad();
  }, WORKER_TIMEOUT);

  tempWorker.addEventListener(
    'message',
    (event: MessageEvent<EmojiWorkerMessage>) => {
      const { data: message } = event;

      worker ??= tempWorker;
      clearTimeout(timeoutId);

      const { type } = message;
      if (type === 'log') {
        workerLog(message.message);
      } else if (type === 'done' && message.storeName === 'custom') {
        void loadEmojisToStore();
      } else if (type === 'db-blocked') {
        window.dispatchEvent(new Event(EMOJI_DB_RELOAD_EVENT));
      }

      if (type !== 'ready') {
        return; // Exit for other messages.
      }

      const debugValue = localStorage.getItem('debug');
      if (debugValue) {
        messageWorker({ type: 'debug', debugValue });
      }

      workerLog('loading data');
      messageWorker(userLocale);
      messageWorker('custom');
      messageWorker('shortcodes');
      void loadEmojisToStore();
    },
  );
}

async function fallbackLoad() {
  log('falling back to main thread for loading');
<<<<<<< HEAD
  const { importCustomEmojiData } = await import('./loader');
  const emojis = await importCustomEmojiData();
  if (emojis) {
    log('loaded %d custom emojis', emojis.length);
  }
  await loadEmojiLocale(userLocale);
  if (userLocale !== 'en') {
    await loadEmojiLocale('en');
=======

  const { importCustomEmojiData, importLegacyShortcodes, importEmojiData } =
    await import('./loader');

  const customEmojis = await importCustomEmojiData();
  if (customEmojis && customEmojis.length > 0) {
    log('loaded %d custom emojis', customEmojis.length);
>>>>>>> origin/trunk
  }

  const shortcodes = await importLegacyShortcodes();
  if (shortcodes?.length) {
    log('loaded %d legacy shortcodes', shortcodes.length);
  }

  const emojis = await importEmojiData(userLocale);
  if (emojis) {
    log('loaded %d emojis to locale %s', emojis.length, userLocale);
  }
  await loadEmojisToStore();
}

<<<<<<< HEAD
async function loadEmojiLocale(localeString: string) {
  const locale = toSupportedLocale(localeString);
  const { importEmojiData, localeToPath } = await import('./loader');

  if (worker) {
    const path = await localeToPath(locale);
    log('asking worker to load locale %s from %s', locale, path);
    messageWorker(locale, path);
  } else {
    const emojis = await importEmojiData(locale);
    if (emojis) {
      log('loaded %d emojis to locale %s', emojis.length, locale);
    }
  }
}

function messageWorker(locale: LocaleOrCustom, path?: string) {
  if (!worker) {
    return;
  }
  worker.postMessage({ locale, path });
=======
export async function loadCustomEmoji() {
  if (worker) {
    messageWorker('custom');
  } else {
    const { importCustomEmojiData } = await import('./loader');
    const emojis = await importCustomEmojiData();
    if (emojis && emojis.length > 0) {
      log('loaded %d custom emojis', emojis.length);
    }
  }
  await loadEmojisToStore();
}

function messageWorker(data: EmojiWorkerMessage | string) {
  if (!worker) {
    return;
  }
  if (typeof data === 'string') {
    worker.postMessage({
      type: 'load',
      storeName: data,
    } satisfies EmojiWorkerMessage);
  } else {
    worker.postMessage(data);
  }
}

async function loadEmojisToStore() {
  const { store } = await import('@/mastodon/store');
  const { loadCustomEmojis, loadLocale } =
    await import('@/mastodon/reducers/slices/emojis');

  loadLocale(userLocale);
  await store.dispatch(loadCustomEmojis());

  log('loaded emoji data into store');
}

async function handleEmojiDbReload() {
  log('Emoji database reload needed, triggering warning');
  const { store } = await import('@/mastodon/store');
  const { needsReload } = await import('@/mastodon/actions/app');
  store.dispatch(needsReload());
>>>>>>> origin/trunk
}
