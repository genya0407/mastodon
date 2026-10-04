# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::ProcessingWorker do
  subject { described_class.new }

  let(:account) { Fabricate(:account) }

  describe '#perform' do
    it 'delegates to ActivityPub::ProcessActivityService' do
      allow(ActivityPub::ProcessActivityService).to receive(:new)
        .and_return(instance_double(ActivityPub::ProcessActivityService, call: nil))
      subject.perform(account.id, '')
      expect(ActivityPub::ProcessActivityService).to have_received(:new)
    end
  end

  describe 'when retries are exhausted after a status fetch failure' do
    let(:recipient) { Fabricate(:account, locked: true) }
    let(:body) do
      {
        '@context': 'https://www.w3.org/ns/activitystreams',
        id: 'foo',
        type: 'Follow',
        actor: ActivityPub::TagManager.instance.uri_for(account),
        object: ActivityPub::TagManager.instance.uri_for(recipient),
      }.to_json
    end

    it 'rejects the follow request' do
      allow(ActivityPub::ProcessActivityService).to receive(:new)
        .and_raise(ActivityPub::Activity::Follow::StatusFetchError)

      expect do
        described_class.within_sidekiq_retries_exhausted_block(
          'args' => [account.id, body],
          'error_class' => 'ActivityPub::Activity::Follow::StatusFetchError'
        ) do
          subject.perform(account.id, body)
        end
      end.to raise_error(ActivityPub::Activity::Follow::StatusFetchError)

      expect(ActivityPub::DeliveryWorker).to have_enqueued_sidekiq_job(
        match_json_values(type: 'Reject', object: include(type: 'Follow')),
        recipient.id,
        anything
      )
    end

    it 'does not reject if the follow request already exists' do
      FollowRequest.create!(account: account, target_account: recipient, uri: 'foo')
      allow(ActivityPub::ProcessActivityService).to receive(:new)
        .and_raise(ActivityPub::Activity::Follow::StatusFetchError)

      expect do
        described_class.within_sidekiq_retries_exhausted_block(
          'args' => [account.id, body],
          'error_class' => 'ActivityPub::Activity::Follow::StatusFetchError'
        ) do
          subject.perform(account.id, body)
        end
      end.to raise_error(ActivityPub::Activity::Follow::StatusFetchError)

      expect(ActivityPub::DeliveryWorker.jobs).to be_empty
    end
  end
end
