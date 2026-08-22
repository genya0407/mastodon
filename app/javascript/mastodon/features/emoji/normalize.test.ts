import { readdir } from 'fs/promises';
import { basename, resolve } from 'path';

import { flattenEmojiData } from 'emojibase';
import unicodeRawEmojis from 'emojibase-data/en/data.json';

import { extractTokens, unicodeToTwemojiHex } from './normalize';

const emojiSVGFiles = await readdir(
  // This assumes tests are run from project root
  resolve(process.cwd(), 'public/emoji'),
  {
    withFileTypes: true,
  },
);
const svgFileNames = emojiSVGFiles
  .filter((file) => file.isFile() && file.name.endsWith('.svg'))
  .map((file) => basename(file.name, '.svg'));
const svgFileNamesWithoutBorder = svgFileNames.filter(
  (fileName) => !fileName.endsWith('_border'),
);

const unicodeEmojis = flattenEmojiData(unicodeRawEmojis);

<<<<<<< HEAD
describe('emojiToUnicodeHex', () => {
  test.concurrent.for([
    ['🎱', '1F3B1'],
    ['🐜', '1F41C'],
    ['⚫', '26AB'],
    ['🖤', '1F5A4'],
    ['💀', '1F480'],
    ['❤️', '2764'], // Checks for trailing variation selector removal.
    ['💂‍♂️', '1F482-200D-2642-FE0F'],
  ] as const)(
    'emojiToUnicodeHex converts %s to %s',
    ([emoji, hexcode], { expect }) => {
      expect(emojiToUnicodeHex(emoji)).toBe(hexcode);
    },
  );
});

=======
>>>>>>> origin/trunk
describe('unicodeToTwemojiHex', () => {
  test.concurrent.for(
    unicodeEmojis
      // Our version of Twemoji only supports up to version 15.1
      .filter((emoji) => emoji.version < 16)
      .map((emoji) => [emoji.hexcode, emoji.label] as [string, string]),
  )('verifying an emoji exists for %s (%s)', ([hexcode], { expect }) => {
    const result = unicodeToTwemojiHex(hexcode);
    expect(svgFileNamesWithoutBorder).toContain(result);
  });
});

describe('extractTokens', () => {
  test('returns an empty array for blank input', () => {
    expect(extractTokens('   ', null)).toEqual([]);
  });

  test('check token word breaking with Intl.Segmenter', () => {
    const segmenter = new Intl.Segmenter('en', { granularity: 'word' });

    expect(
      extractTokens('thumbs_up smiling-face camelCase', segmenter),
    ).toEqual(['thumbs', 'up', 'smiling', 'face', 'camel', 'case']);
  });

  test('check token word breaking with regex', () => {
    expect(extractTokens('Smile_face joy-test A ok 7 z', null)).toEqual([
      'smile',
      'face',
      'joy',
      'test',
      'ok',
    ]);
  });

  test('ensure +1 and -1 are preserved', () => {
    expect(extractTokens('+1', null)).toEqual(['+1']);
    expect(extractTokens('-1', null)).toEqual(['-1']);
  });
});
