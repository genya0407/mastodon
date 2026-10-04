# frozen_string_literal: true

class ActivityPub::ProcessingWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'ingress', backtrace: true, retry: 8

  sidekiq_retries_exhausted do |msg, _exception|
    ActivityPub::ProcessingWorker.reject_follow_request_after_status_fetch_failure(msg)
  end

  def self.reject_follow_request_after_status_fetch_failure(msg)
    return unless msg['error_class'] == 'ActivityPub::Activity::Follow::StatusFetchError'

    actor_id, body, _delivered_to_account_id, actor_type = msg['args']
    return if actor_type.present? && actor_type != 'Account'

    actor = ActiveRecord::Base.connection_pool.with_connection do
      Account.find_by(id: actor_id)
    end
    return if actor.nil?

    json = JSON.parse(body)
    return unless json['type'] == 'Follow'
    return unless json['actor'] == ActivityPub::TagManager.instance.uri_for(actor)

    activity = ActivityPub::Activity.factory(json.with_indifferent_access, actor)
    return unless activity.is_a?(ActivityPub::Activity::Follow)

    ActiveRecord::Base.connection_pool.with_connection do
      activity.reject_follow_request_after_status_fetch_failure!
    end
  rescue JSON::ParserError
    nil
  rescue StandardError => e
    Rails.logger.error { "Failed to reject follow request after status fetch retries were exhausted: #{e}" }
    nil
  end

  def perform(actor_id, body, delivered_to_account_id = nil, actor_type = 'Account')
    case actor_type
    when 'Account'
      actor = Account.find_by(id: actor_id)
    end

    return if actor.nil?

    ActivityPub::ProcessActivityService.new.call(body, actor, override_timestamps: true, delivered_to_account_id: delivered_to_account_id, delivery: true)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.debug { "Error processing incoming ActivityPub object: #{e}" }
  end
end
