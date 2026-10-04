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
      allow(Rails.logger).to receive(:warn)

      ClimateControl.modify AUTO_REJECT_FOLLOW_REQUEST_ENABLED: 'true',
                            AUTO_REJECT_FOLLOW_REQUEST_STATUS_COUNT: '2',
                            AUTO_REJECT_FOLLOW_REQUEST_PHRASES: 'unwanted phrase' do
        expect do
          described_class.within_sidekiq_retries_exhausted_block(
            'args' => [account.id, body],
            'error_class' => 'ActivityPub::Activity::Follow::StatusFetchError'
          ) do
            subject.perform(account.id, body)
          end
        end.to raise_error(ActivityPub::Activity::Follow::StatusFetchError)
      end

      expect(Rails.logger).to have_received(:warn)
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

    it 'logs the candidate but does not reject when disabled' do
      allow(ActivityPub::ProcessActivityService).to receive(:new)
        .and_raise(ActivityPub::Activity::Follow::StatusFetchError)
      allow(Rails.logger).to receive(:warn)

      ClimateControl.modify AUTO_REJECT_FOLLOW_REQUEST_ENABLED: 'false',
                            AUTO_REJECT_FOLLOW_REQUEST_STATUS_COUNT: '2',
                            AUTO_REJECT_FOLLOW_REQUEST_PHRASES: 'unwanted phrase' do
        expect do
          described_class.within_sidekiq_retries_exhausted_block(
            'args' => [account.id, body],
            'error_class' => 'ActivityPub::Activity::Follow::StatusFetchError'
          ) do
            subject.perform(account.id, body)
          end
        end.to raise_error(ActivityPub::Activity::Follow::StatusFetchError)
      end

      expect(Rails.logger).to have_received(:warn)
      expect(ActivityPub::DeliveryWorker.jobs).to be_empty
    end
  end
end
