# frozen_string_literal: true

class REST::ReactedStatusSerializer < REST::StatusSerializer
  def content
    original_content = super
    return original_content if !object.local? || object.emoji_count.empty?

    parsed_original_content = Nokogiri::HTML::DocumentFragment.parse(original_content)
    Nokogiri::HTML::Builder.with(parsed_original_content) do |doc|
      doc.p do
        object.emoji_count.each do |emoji, count|
          doc.span do
            if emoji.start_with?('http')
              doc.img(height: '30').src = Rails.cache.fetch("reacted_status_serializer:image:#{Digest::MD5.hexdigest(emoji)}", expires_in: 24.hours) do
                base64 = Base64.strict_encode64(Net::HTTP.get_response(URI.parse(emoji)).body)
                "data:image/png;base64,#{base64}"
              end
              doc.span(" (#{count})")
            else
              doc.span("#{emoji} (#{count})")
            end
          end
        end
      end
    end
    parsed_original_content.to_html
  end
end
