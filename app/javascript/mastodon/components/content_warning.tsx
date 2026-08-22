import { useStatus } from '../hooks/useStatus';

import { EmojiHTML } from './emoji/html';
import { StatusBanner, BannerVariant } from './status_banner';

export const ContentWarning: React.FC<{
  statusId: string;
  expanded?: boolean;
  onClick?: () => void;
}> = ({ statusId, expanded, onClick }) => {
  const status = useStatus(statusId);
  const hasSpoiler = !!status?.spoiler_text;
  const text = status?.translation?.spoilerHtml ?? status?.spoilerHtml;
  if (!hasSpoiler || !text) {
    return null;
  }

  return (
    <StatusBanner
      expanded={expanded}
      onClick={onClick}
      variant={BannerVariant.Warning}
    >
<<<<<<< HEAD
      <EmojiHTML
        as='span'
        htmlString={text}
        extraEmojis={status.get('emojis') as List<CustomEmoji>}
      />
=======
      <EmojiHTML as='span' htmlString={text} extraEmojis={status.emojis} />
>>>>>>> origin/trunk
    </StatusBanner>
  );
};
