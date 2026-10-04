# frozen_string_literal: true

class ActivityPub::Activity::Follow < ActivityPub::Activity
  include Payloadable

  DEFAULT_STATUS_COUNT = 5
  MAX_STATUS_COUNT = 100
  OUTBOX_ITEMS_PER_STATUS = 5
  MIN_OUTBOX_PAGES = 5

  private_constant :DEFAULT_STATUS_COUNT, :MAX_STATUS_COUNT, :OUTBOX_ITEMS_PER_STATUS, :MIN_OUTBOX_PAGES

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
    return if existing_follow_relationship?(target_account)

    reject_follow_request!(target_account)
  end

  private

  def existing_follow_relationship?(target_account)
    FollowRequest.exists?(account: @account, target_account: target_account) ||
      Follow.exists?(account: @account, target_account: target_account)
  end

  def reject_follow_request_for_status_content?(target_account)
    status_count = auto_reject_status_count
    return false unless status_count.positive?

    phrases = auto_reject_phrases
    return false if phrases.empty?

    statuses = recent_distributable_statuses(status_count, target_account)
    statuses.any? do |status|
      status_text = normalize_status_text(Nokogiri::HTML5.fragment([status.spoiler_text, status.text].join("\n")).text)
      phrases.any? { |phrase| status_text.include?(phrase) }
    end
  end

  def auto_reject_status_count
    [ENV.fetch('AUTO_REJECT_FOLLOW_REQUEST_STATUS_COUNT', DEFAULT_STATUS_COUNT.to_s).to_i, MAX_STATUS_COUNT].min
  end

  def auto_reject_phrases
    ENV.fetch('AUTO_REJECT_FOLLOW_REQUEST_PHRASES', '')
      .split(',')
      .map(&:strip)
      .reject(&:blank?)
      .map { |phrase| normalize_status_text(phrase) }
  end

  def recent_distributable_statuses(status_count, target_account)
    statuses = @account.statuses.without_reblogs.distributable_visibility.reorder(id: :desc).limit(status_count).to_a
    return statuses if statuses.size >= status_count

    item_limit = [status_count * OUTBOX_ITEMS_PER_STATUS, MAX_STATUS_COUNT].min
    items, = collection_items(
      @account.outbox_url,
      max_pages: [status_count, MIN_OUTBOX_PAGES].max,
      max_items: item_limit,
      reference_uri: @account.uri,
      on_behalf_of: target_account
    )
    raise StatusFetchError, 'Could not fetch the sender outbox' if items.nil?

    fetched_statuses = []
    failed_fetch = false
    fetch_service = ActivityPub::FetchRemoteStatusService.new
    items.each do |item|
      next unless status_activity?(item)

      uri = value_or_id(item)
      if uri.blank?
        failed_fetch = true
        next
      end

      next if already_stored_status?(item, uri)

      status = fetch_service.call(
        uri,
        on_behalf_of: target_account,
        expected_actor_uri: @account.uri,
        request_id: @options[:request_id]
      )
      if status.nil?
        failed_fetch = true
        next
      end
      raise StatusFetchError, "Fetched sender status #{uri} belongs to another account" if status.account_id != @account.id

      if status.distributable? && !status.reblog? && statuses.exclude?(status)
        fetched_statuses << status
        break if statuses.size + fetched_statuses.size >= status_count
      end
    end

    raise StatusFetchError, 'Could not fetch enough recent sender statuses' if failed_fetch && statuses.size + fetched_statuses.size < status_count

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

  def already_stored_status?(item, uri)
    status_uri = item.is_a?(Hash) ? value_or_id(item['object']) : uri
    status_uri.present? && @account.statuses.exists?(uri: status_uri)
  end

  def normalize_status_text(text)
    text.unicode_normalize(:nfkc).downcase
  end
end
