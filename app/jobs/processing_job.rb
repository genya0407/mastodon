# frozen_string_literal: true

class ProcessingJob < ApplicationJob
  queue_as :default

  retry_on StandardError, attempts: 8

  def perform(actor_id, body, delivered_to_account_id = nil, actor_type = 'Account')
    case actor_type
    when 'Account'
      actor = Account.find_by(id: actor_id)
    end

    return if actor.nil?

    ActivityPub::ProcessCollectionService.new.call(body, actor, override_timestamps: true, delivered_to_account_id: delivered_to_account_id, delivery: true)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.debug { "Error processing incoming ActivityPub object: #{e}" }
  end
end
