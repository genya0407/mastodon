# frozen_string_literal: true

class LinkCrawlJob < ApplicationJob
  queue_as :default

  def perform(status_id)
    FetchLinkCardService.new.call(Status.find(status_id))
  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique
    true
  end
end
