# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::Activity::Follow do
  let(:sender)    { Fabricate(:account) }
  let(:recipient) { Fabricate(:account) }

  let(:json) do
    {
      '@context': 'https://www.w3.org/ns/activitystreams',
      id: 'foo',
      type: 'Follow',
      actor: ActivityPub::TagManager.instance.uri_for(sender),
      object: ActivityPub::TagManager.instance.uri_for(recipient),
    }.with_indifferent_access
  end

  describe '#perform' do
    subject { described_class.new(json, sender) }

    context 'with no prior follow' do
      context 'with an unlocked account' do
        before do
          subject.perform
        end

        it 'creates a follow from sender to recipient' do
          expect(sender.following?(recipient)).to be true
          expect(sender.active_relationships.find_by(target_account: recipient).uri).to eq 'foo'
        end

        it 'does not create a follow request' do
          expect(sender.requested?(recipient)).to be false
        end
      end

      context 'when silenced account following an unlocked account' do
        before do
          sender.touch(:silenced_at)
          subject.perform
        end

        it 'does not create a follow from sender to recipient' do
          expect(sender.following?(recipient)).to be false
        end

        it 'creates a follow request' do
          expect(sender.requested?(recipient)).to be true
          expect(sender.follow_requests.find_by(target_account: recipient).uri).to eq 'foo'
        end
      end

      context 'with an unlocked account muting the sender' do
        before do
          recipient.mute!(sender)
          subject.perform
        end

        it 'creates a follow from sender to recipient' do
          expect(sender.following?(recipient)).to be true
          expect(sender.active_relationships.find_by(target_account: recipient).uri).to eq 'foo'
        end

        it 'does not create a follow request' do
          expect(sender.requested?(recipient)).to be false
        end
      end

      context 'when locked account' do
        before do
          recipient.update(locked: true)
          subject.perform
        end

        it 'does not create a follow from sender to recipient' do
          expect(sender.following?(recipient)).to be false
        end

        it 'creates a follow request' do
          expect(sender.requested?(recipient)).to be true
          expect(sender.follow_requests.find_by(target_account: recipient).uri).to eq 'foo'
        end
      end

      context 'when locked account automatically rejects matching recent posts' do
        before do
          recipient.update!(locked: true)
          Fabricate(:status, account: sender, text: '<p>This contains an unwanted phrase.</p>')
        end

        it 'rejects the follow without creating a follow request' do
          ClimateControl.modify AUTO_REJECT_FOLLOW_REQUEST_STATUS_COUNT: '1',
                                AUTO_REJECT_FOLLOW_REQUEST_PHRASES: 'other phrase, unwanted phrase' do
            expect { subject.perform }
              .to not_change { FollowRequest.count }
              .and change { ActivityPub::DeliveryWorker.jobs.size }.by(1)
          end

          expect(sender.requested?(recipient)).to be false
          expect(ActivityPub::DeliveryWorker).to have_enqueued_sidekiq_job(
            match_json_values(type: 'Reject', object: include(type: 'Follow')),
            recipient.id,
            anything
          )
        end

        it 'does not reject based on posts older than the configured limit' do
          Fabricate(:status, account: sender, text: 'recent post')
          ClimateControl.modify AUTO_REJECT_FOLLOW_REQUEST_STATUS_COUNT: '1',
                                AUTO_REJECT_FOLLOW_REQUEST_PHRASES: 'unwanted phrase' do
            expect { subject.perform }
              .to change { FollowRequest.where(account: sender, target_account: recipient).count }.by(1)
          end
        end

        it 'uses the default empty phrase list when not configured' do
          ClimateControl.modify AUTO_REJECT_FOLLOW_REQUEST_STATUS_COUNT: nil,
                                AUTO_REJECT_FOLLOW_REQUEST_PHRASES: nil do
            expect { subject.perform }
              .to change { FollowRequest.where(account: sender, target_account: recipient).count }.by(1)
          end
        end

        it 'checks five posts by default' do
          Fabricate(:status, account: sender, text: 'unwanted phrase')
          5.times { Fabricate(:status, account: sender, text: 'recent post') }

          ClimateControl.modify AUTO_REJECT_FOLLOW_REQUEST_STATUS_COUNT: nil,
                                AUTO_REJECT_FOLLOW_REQUEST_PHRASES: 'unwanted phrase' do
            expect { subject.perform }
              .to change { FollowRequest.where(account: sender, target_account: recipient).count }.by(1)
          end
        end
      end

      context 'when the sender has fewer local statuses than the configured limit' do
        before do
          recipient.update!(locked: true)
          Fabricate(:status, account: sender, text: 'A recent post without a match')
        end

        let(:fetch_service) { instance_double(ActivityPub::FetchRemoteStatusService) }

        before do
          allow(subject).to receive(:collection_items)
            .and_return([['https://example.com/status/2'], 1])
          allow(ActivityPub::FetchRemoteStatusService).to receive(:new).and_return(fetch_service)
        end

        it 'fetches the sender status before checking its content' do
          allow(fetch_service).to receive(:call) do
            Fabricate(:status, account: sender, text: 'This post contains an unwanted phrase.')
          end

          ClimateControl.modify AUTO_REJECT_FOLLOW_REQUEST_STATUS_COUNT: '2',
                                AUTO_REJECT_FOLLOW_REQUEST_PHRASES: 'unwanted phrase' do
            expect { subject.perform }
              .to not_change { FollowRequest.where(account: sender, target_account: recipient).count }
          end

          expect(fetch_service).to have_received(:call).with(
            'https://example.com/status/2',
            on_behalf_of: recipient,
            expected_actor_uri: sender.uri,
            request_id: nil
          )
          expect(ActivityPub::DeliveryWorker).to have_enqueued_sidekiq_job(
            match_json_values(type: 'Reject', object: include(type: 'Follow')),
            recipient.id,
            anything
          )
        end

        it 'raises a retryable error when the status cannot be fetched' do
          allow(fetch_service).to receive(:call).and_return(nil)

          ClimateControl.modify AUTO_REJECT_FOLLOW_REQUEST_STATUS_COUNT: '2',
                                AUTO_REJECT_FOLLOW_REQUEST_PHRASES: 'unwanted phrase' do
            expect { subject.perform }
              .to raise_error(ActivityPub::Activity::Follow::StatusFetchError)
          end

          expect(FollowRequest.where(account: sender, target_account: recipient)).to be_empty
        end

        it 'raises a retryable error when the sender outbox cannot be fetched' do
          allow(subject).to receive(:collection_items).and_return([nil, 0])

          ClimateControl.modify AUTO_REJECT_FOLLOW_REQUEST_STATUS_COUNT: '2',
                                AUTO_REJECT_FOLLOW_REQUEST_PHRASES: 'unwanted phrase' do
            expect { subject.perform }
              .to raise_error(ActivityPub::Activity::Follow::StatusFetchError)
          end
        end

        it 'raises a retryable error when a public outbox item has no URI' do
          allow(subject).to receive(:collection_items).and_return([
            [{ 'type' => 'Create', 'to' => ['Public'] }],
            1,
          ])

          ClimateControl.modify AUTO_REJECT_FOLLOW_REQUEST_STATUS_COUNT: '2',
                                AUTO_REJECT_FOLLOW_REQUEST_PHRASES: 'unwanted phrase' do
            expect { subject.perform }
              .to raise_error(ActivityPub::Activity::Follow::StatusFetchError)
          end
        end

        it 'raises a retryable error when a fetched status belongs to another account' do
          allow(fetch_service).to receive(:call).and_return(Fabricate(:status, account: Fabricate(:account)))

          ClimateControl.modify AUTO_REJECT_FOLLOW_REQUEST_STATUS_COUNT: '2',
                                AUTO_REJECT_FOLLOW_REQUEST_PHRASES: 'unwanted phrase' do
            expect { subject.perform }
              .to raise_error(ActivityPub::Activity::Follow::StatusFetchError)
          end
        end

        it 'skips non-Create and non-public outbox items' do
          expect(subject.send(:status_activity?, 'type' => 'Announce')).to be false
          expect(subject.send(:status_activity?, 'type' => 'Create', 'to' => ['https://example.com/followers'])).to be false
        end
      end
    end

    context 'when recipient blocks sender' do
      before { Fabricate :block, account: recipient, target_account: sender }

      it 'sends a reject and does not follow' do
        subject.perform

        expect(sender.requested?(recipient))
          .to be false
        expect(ActivityPub::DeliveryWorker)
          .to have_enqueued_sidekiq_job(
            match_json_values(type: 'Reject', object: include(type: 'Follow')),
            recipient.id,
            anything
          )
      end
    end

    context 'when a follow relationship already exists' do
      before do
        sender.active_relationships.create!(target_account: recipient, uri: 'bar')
      end

      context 'with an unlocked account' do
        before do
          subject.perform
        end

        it 'correctly sets the new URI' do
          expect(sender.active_relationships.find_by(target_account: recipient).uri).to eq 'foo'
        end

        it 'does not create a follow request' do
          expect(sender.requested?(recipient)).to be false
        end
      end

      context 'when silenced account following an unlocked account' do
        before do
          sender.touch(:silenced_at)
          subject.perform
        end

        it 'correctly sets the new URI' do
          expect(sender.active_relationships.find_by(target_account: recipient).uri).to eq 'foo'
        end

        it 'does not create a follow request' do
          expect(sender.requested?(recipient)).to be false
        end
      end

      context 'with an unlocked account muting the sender' do
        before do
          recipient.mute!(sender)
          subject.perform
        end

        it 'correctly sets the new URI' do
          expect(sender.active_relationships.find_by(target_account: recipient).uri).to eq 'foo'
        end

        it 'does not create a follow request' do
          expect(sender.requested?(recipient)).to be false
        end
      end

      context 'when locked account' do
        before do
          recipient.update(locked: true)
          subject.perform
        end

        it 'correctly sets the new URI' do
          expect(sender.active_relationships.find_by(target_account: recipient).uri).to eq 'foo'
        end

        it 'does not create a follow request' do
          expect(sender.requested?(recipient)).to be false
        end
      end
    end

    context 'when a follow request already exists' do
      before do
        sender.follow_requests.create!(target_account: recipient, uri: 'bar')
      end

      context 'when silenced account following an unlocked account' do
        before do
          sender.touch(:silenced_at)
          subject.perform
        end

        it 'does not create a follow from sender to recipient' do
          expect(sender.following?(recipient)).to be false
        end

        it 'correctly sets the new URI' do
          expect(sender.requested?(recipient)).to be true
          expect(sender.follow_requests.find_by(target_account: recipient).uri).to eq 'foo'
        end
      end

      context 'when locked account' do
        before do
          recipient.update(locked: true)
          subject.perform
        end

        it 'does not create a follow from sender to recipient' do
          expect(sender.following?(recipient)).to be false
        end

        it 'correctly sets the new URI' do
          expect(sender.requested?(recipient)).to be true
          expect(sender.follow_requests.find_by(target_account: recipient).uri).to eq 'foo'
        end
      end
    end
  end
end
