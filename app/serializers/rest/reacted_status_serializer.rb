# frozen_string_literal: true

class REST::ReactedStatusSerializer < REST::StatusSerializer
  def content
    original_content = Nokogiri::HTML::DocumentFragment.parse(super)
    return original_content if !object.local? || object.emoji_count.empty?

    Nokogiri::HTML::Builder.with(original_content) do |doc|
      object.emoji_count.each do |emoji, count|
        doc.span do
          if emoji.start_with?('http')
            doc.img(height: '30').src = emoji
            doc.span(" (#{count})")
          else
            doc.span("#{emoji} (#{count})")
          end
        end
      end
    end
    original_content.to_html
  end
end
