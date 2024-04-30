# frozen_string_literal: true

class REST::ReactedStatusSerializer < REST::StatusSerializer
  def content
    original_content = super
    return original_content if !object.local? || object.emoji_count.empty?

    parsed_original_content = Nokogiri::HTML::DocumentFragment.parse(original_content)
    Nokogiri::HTML::Builder.with(parsed_original_content) do |doc|
      doc.p do
        object.emoji_count.each.with_index do |(emoji, count), i|
          doc.span do
            if emoji.start_with?('http')
              doc.span(":__emoji_reaction_#{i}: (#{count})")
            else
              doc.span("#{emoji} (#{count})")
            end
          end
        end
      end
    end
    parsed_original_content.to_html
  end

  def to_h
    super.tap do |hash|
      hash[:emojis] += object.emoji_count.map.with_index do |(emoji, _), i|
        next unless emoji.start_with?('http')

        {
          shortcode: "__emoji_reaction_#{i}",
          url: emoji,
          static_url: emoji,
          visible_in_pick: true,
        }
      end.compact
    end
  end
end
