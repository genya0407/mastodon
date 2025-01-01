# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RemoveDomainsFromFollowersService do
  describe '#call' do
    context 'with account followers' do
      let(:account) { Fabricate(:account, domain: nil) }
      let(:good_domain_account) { Fabricate(:account, domain: 'good.example', protocol: :activitypub) }
      let(:bad_domain_account) { Fabricate(:account, domain: 'bad.example', protocol: :activitypub) }

      before do
        Fabricate :follow, target_account: account, account: good_domain_account
        Fabricate :follow, target_account: account, account: bad_domain_account
      end

      it 'removes followers from supplied domains and sends a notification' do
        expect do
          subject.call(account, ['bad.example'])
        end.to have_enqueued_job(ActivityPub::DeliveryJob).with(anything, account.id, bad_domain_account.inbox_url)

        expect(account.followers)
          .to include(good_domain_account)
          .and not_include(bad_domain_account)
      end
    end
  end
end
