# frozen_string_literal: true

class ActivityPub::Activity::Follow < ActivityPub::Activity
  include Payloadable

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

  private

  def reject_follow_request_for_status_content?(target_account)
    user = target_account.user
    return false if user.nil?

    status_count = user.settings['auto_reject_follow_request_status_count'].to_i
    return false unless status_count.positive?

    phrases = user.settings['auto_reject_follow_request_phrases'].to_s.lines.map(&:strip).reject(&:blank?)
    return false if phrases.empty?

    normalized_phrases = phrases.map { |phrase| normalize_status_text(phrase) }
    statuses = @account.statuses.without_reblogs.distributable_visibility.reorder(id: :desc).limit([status_count, 100].min)

    statuses.pluck(:text, :spoiler_text).any? do |text, spoiler_text|
      status_text = normalize_status_text(Nokogiri::HTML5.fragment([spoiler_text, text].join("\n")).text)
      normalized_phrases.any? { |phrase| status_text.include?(phrase) }
    end
  end

  def normalize_status_text(text)
    text.unicode_normalize(:nfkc).downcase
  end
end
