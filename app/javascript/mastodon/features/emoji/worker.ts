<<<<<<< HEAD
import { importCustomEmojiData, importEmojiData } from './loader';
=======
import debug from 'debug';

import { EMOJI_DB_NAME_SHORTCODES, EMOJI_TYPE_CUSTOM } from './constants';
import {
  importCustomEmojiData,
  importEmojiData,
  importLegacyShortcodes,
} from './loader';
import type { EmojiWorkerMessage } from './types';
>>>>>>> origin/trunk

addEventListener('message', handleMessage);
self.postMessage({ type: 'ready' } satisfies EmojiWorkerMessage); // After the worker is ready, notify the main thread

<<<<<<< HEAD
function handleMessage(event: MessageEvent<{ locale: string; path?: string }>) {
  const {
    data: { locale, path },
  } = event;
  void loadData(locale, path);
}

async function loadData(locale: string, path?: string) {
  let importCount: number | undefined;
  if (locale === 'custom') {
    importCount = (await importCustomEmojiData())?.length;
  } else if (path) {
    importCount = (await importEmojiData(locale, path))?.length;
  } else {
    throw new Error('Path is required for loading locale emoji data');
  }
  if (importCount) {
    self.postMessage(`loaded ${importCount} emojis into ${locale}`);
=======
function handleMessage(event: MessageEvent<EmojiWorkerMessage>) {
  const { data } = event;
  if (data.type === 'debug') {
    debug.enable(data.debugValue);
  } else if (data.type === 'load') {
    void loadData(data.storeName);
  }
}

async function loadData(storeName: string) {
  let importCount: number | undefined;
  if (storeName === EMOJI_TYPE_CUSTOM) {
    importCount = (await importCustomEmojiData())?.length;
  } else if (storeName === EMOJI_DB_NAME_SHORTCODES) {
    importCount = (await importLegacyShortcodes())?.length;
  } else {
    importCount = (await importEmojiData(storeName))?.length;
  }

  if (importCount) {
    self.postMessage({
      type: 'done',
      storeName,
      importCount,
    } satisfies EmojiWorkerMessage);
>>>>>>> origin/trunk
  }
}
