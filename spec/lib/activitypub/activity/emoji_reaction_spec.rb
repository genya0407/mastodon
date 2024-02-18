# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'emoji reaction' do # rubocop:disable RSpec/DescribeClass
  let(:sender)    { Fabricate(:account) }
  let(:recipient) { Fabricate(:account) }
  let(:status)    { Fabricate(:status, account: recipient) }

  let(:base_json) do
    {
      '@context': 'https://www.w3.org/ns/activitystreams',
      id: 'foo',
      type: 'Like',
      actor: ActivityPub::TagManager.instance.uri_for(sender),
      object: ActivityPub::TagManager.instance.uri_for(status),
    }.with_indifferent_access
  end

  describe '#perform' do
    subject { ActivityPub::Activity::Like.new(json, sender) }

    before do
      subject.perform
    end

    context 'when content nor tags is present' do
      let(:json) { base_json }

      it 'creates a favourite from sender to status' do
        expect(sender.favourited?(status)).to be true
      end
    end

    context 'when content is present' do
      let(:json) { base_json.merge(content: ':some_emoji:') }

      it 'creates a favourite from sender to status' do
        expect(sender.favourited?(status)).to be true
      end

      it 'creates a favourite with emoji' do
        expect(status.favourites.first.emoji).to eq ':some_emoji:'
      end
    end

    context 'when tag is present' do
      let(:json) { base_json.merge(content: ':some_emoji:', tag: [{ icon: { url: 'https://...' } }]) }

      it 'creates a favourite from sender to status' do
        expect(sender.favourited?(status)).to be true
      end

      it 'creates a favourite with emoji' do
        expect(status.favourites.first.emoji).to eq 'https://...'
      end
    end
  end
end
