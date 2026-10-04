# frozen_string_literal: true

class ActivityPub::Activity::Follow < ActivityPub::Activity
  include Payloadable

  class StatusFetchError < StandardError; end

  def perform
    target_account = account_from_uri(object_uri)

    return if target_account.nil? || !target_account.local? || delete_arrived_first?(@json['id'])

    # Update id of already-existing follow requests
    existing_follow_request = ::FollowRequest.find_by(account: @account, target_account: target_account)
    unless existing_follow_request.nil?
      existing_follow_request.update!(uri: @json['id'])
      return
    end

    if target_account.blocking?(@account) || target_account.domain_blocking?(@account.domain) || target_account.moved? || target_account.instance_actor?
      reject_follow_request!(target_account)
      return
    end

    # Fast-forward repeat follow requests
    existing_follow = ::Follow.find_by(account: @account, target_account: target_account)
    unless existing_follow.nil?
      existing_follow.update!(uri: @json['id'])
      AuthorizeFollowService.new.call(@account, target_account, skip_follow_request: true, follow_request_uri: @json['id'])
      return
    end

    requires_follow_request = target_account.locked? || @account.silenced?

    if requires_follow_request && reject_follow_request_for_status_content?(target_account)
      reject_follow_request!(target_account)
      return
    end

    follow_request = FollowRequest.create!(account: @account, target_account: target_account, uri: @json['id'])

    if requires_follow_request
      LocalNotificationWorker.perform_async(target_account.id, follow_request.id, 'FollowRequest', 'follow_request')
    else
      AuthorizeFollowService.new.call(@account, target_account)
      LocalNotificationWorker.perform_async(target_account.id, ::Follow.find_by(account: @account, target_account: target_account).id, 'Follow', 'follow')
    end
  end

  def reject_follow_request!(target_account)
    json = serialize_payload(FollowRequest.new(account: @account, target_account: target_account, uri: @json['id']), ActivityPub::RejectFollowSerializer).to_json
    ActivityPub::DeliveryWorker.perform_async(json, target_account.id, @account.inbox_url)
  end

  def reject_follow_request_after_status_fetch_failure!
    target_account = account_from_uri(object_uri)
    return if target_account.nil? || !target_account.local?
    return if FollowRequest.exists?(account: @account, target_account: target_account) || Follow.exists?(account: @account, target_account: target_account)

    reject_follow_request!(target_account)
  end

  private

  def reject_follow_request_for_status_content?(target_account)
    status_count = [ENV.fetch('AUTO_REJECT_FOLLOW_REQUEST_STATUS_COUNT', '5').to_i, 100].min
    return false unless status_count.positive?

    phrases = ENV.fetch('AUTO_REJECT_FOLLOW_REQUEST_PHRASES', '').split(',').map(&:strip).reject(&:blank?)
    return false if phrases.empty?

    statuses = recent_distributable_statuses(status_count, target_account)
    normalized_phrases = phrases.map { |phrase| normalize_status_text(phrase) }
    statuses.any? do |status|
      status_text = normalize_status_text(Nokogiri::HTML5.fragment([status.spoiler_text, status.text].join("\n")).text)
      normalized_phrases.any? { |phrase| status_text.include?(phrase) }
    end
  end

  def recent_distributable_statuses(status_count, target_account)
    statuses = @account.statuses.without_reblogs.distributable_visibility.reorder(id: :desc).limit(status_count).to_a
    return statuses if statuses.size >= status_count

    item_limit = [status_count * 5, 100].min
    items, = collection_items(
      @account.outbox_url,
      max_pages: [status_count, 5].max,
      max_items: item_limit,
      reference_uri: @account.uri,
      on_behalf_of: target_account
    )
    raise StatusFetchError, 'Could not fetch the sender outbox' if items.nil?

    fetched_statuses = []
    items.each do |item|
      next unless status_activity?(item)

      uri = value_or_id(item)
      raise StatusFetchError, 'The sender outbox contains an item without a URI' if uri.blank?

      status = ActivityPub::FetchRemoteStatusService.new.call(
        uri,
        on_behalf_of: target_account,
        expected_actor_uri: @account.uri,
        request_id: @options[:request_id]
      )
      raise StatusFetchError, "Could not fetch sender status #{uri}" if status.nil? || status.account_id != @account.id

      if status.distributable? && !status.reblog? && statuses.exclude?(status)
        fetched_statuses << status
        break if statuses.size + fetched_statuses.size >= status_count
      end
    end

    (statuses + fetched_statuses).uniq(&:id).sort_by(&:id).reverse.take(status_count)
  rescue StatusFetchError
    raise
  rescue StandardError => e
    Rails.logger.warn { "Unable to fetch recent posts for follow request from #{@account.acct}: #{e}" }
    raise StatusFetchError, e.message
  end

  def status_activity?(item)
    return true if item.is_a?(String)
    return false unless item.is_a?(Hash) && item['type'] == 'Create'

    (as_array(item['to']) + as_array(item['cc'])).any? do |audience|
      ActivityPub::TagManager.instance.public_collection?(value_or_id(audience))
    end
  end

  def normalize_status_text(text)
    text.unicode_normalize(:nfkc).downcase
  end
end
