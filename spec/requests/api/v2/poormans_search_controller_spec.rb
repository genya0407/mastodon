# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V2::SearchController do # rubocop:disable RSpec::FilePath
  render_views

  before do
    allow(Chewy).to receive(:enabled?).and_return(false)
  end

  describe 'status search' do
    describe 'GET #index' do
      let(:user)  { Fabricate(:user) }
      let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read:search') }

      before do
        allow(controller).to receive(:doorkeeper_token) { token }
      end

      context 'when query is empty' do
        it 'returns http 400' do
          get :index, params: { q: '' }

          expect(response).to have_http_status(400)
        end
      end

      context 'when there are some statuses' do
        let!(:status_relevant) { Fabricate(:status, text: 'test') }

        before do
          Fabricate(:status, text: 'text')
        end

        it 'returns status' do
          get :index, params: { q: 'test' }

          expect(body_as_json[:statuses].pluck(:id)).to eq [status_relevant.id.to_s]
        end
      end

      context 'when there are some statuses with complex text and query' do
        let!(:status_relevant) { Fabricate(:status, text: 'test あああ') }

        before do
          Fabricate(:status, text: 'test')
          Fabricate(:status, text: 'あああ')
        end

        it 'returns status' do
          get :index, params: { q: 'test　あああ' }

          expect(body_as_json[:statuses].pluck(:id)).to eq [status_relevant.id.to_s]
        end
      end

      context 'when there are some statuses with different users' do
        let!(:alice) { Fabricate(:account, username: 'alice') }
        let!(:bob) { Fabricate(:account, username: 'bob', domain: 'example.com') }
        let!(:alice_status) { Fabricate(:status, text: 'test', account: alice) }
        let!(:bob_status) { Fabricate(:status, text: 'test', account: bob) }

        it 'returns status for alice' do
          get :index, params: { q: 'es from:alice' }

          expect(body_as_json[:statuses].pluck(:id)).to eq [alice_status.id.to_s]
        end

        it 'returns status for @alice' do
          get :index, params: { q: 'es from:@alice' }

          expect(body_as_json[:statuses].pluck(:id)).to eq [alice_status.id.to_s]
        end

        it 'returns status for bob@example.com' do
          get :index, params: { q: 'es from:bob@example.com' }

          expect(body_as_json[:statuses].pluck(:id)).to eq [bob_status.id.to_s]
        end

        it 'returns status for @bob@example.com' do
          get :index, params: { q: 'es from:@bob@example.com' }

          expect(body_as_json[:statuses].pluck(:id)).to eq [bob_status.id.to_s]
        end
      end
    end
  end

  # Followings are copied from search_controller_spec.rb
  context 'with token' do
    let(:user)  { Fabricate(:user) }
    let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read:search') }

    before do
      allow(controller).to receive(:doorkeeper_token) { token }
    end

    describe 'GET #index' do
      let!(:bob)   { Fabricate(:account, username: 'bob_test') }
      let!(:ana)   { Fabricate(:account, username: 'ana_test') }
      let!(:tom)   { Fabricate(:account, username: 'tom_test') }
      let(:params) { { q: 'test' } }

      it 'returns http success' do
        get :index, params: params

        expect(response).to have_http_status(200)
      end

      context 'when searching accounts' do
        let(:params) { { q: 'test', type: 'accounts' } }

        it 'returns all matching accounts' do
          get :index, params: params

          expect(body_as_json[:accounts].pluck(:id)).to contain_exactly(bob.id.to_s, ana.id.to_s, tom.id.to_s)
        end

        context 'with following=true' do
          let(:params) { { q: 'test', type: 'accounts', following: 'true' } }

          before do
            user.account.follow!(ana)
          end

          it 'returns only the followed accounts' do
            get :index, params: params

            expect(body_as_json[:accounts].pluck(:id)).to contain_exactly(ana.id.to_s)
          end
        end
      end
    end
  end

  context 'without token' do
    describe 'GET #index' do
      before do
        get :index, params: search_params
      end

      context 'with a `q` shorter than 5 characters' do
        let(:search_params) { { q: 'test' } }

        it 'returns http success' do
          expect(response).to have_http_status(200)
        end
      end

      context 'with a `q` equal to or longer than 5 characters' do
        let(:search_params) { { q: 'test1' } }

        it 'returns http success' do
          expect(response).to have_http_status(200)
        end

        context 'with truthy `resolve`' do
          let(:search_params) { { q: 'test1', resolve: '1' } }

          it 'returns http unauthorized' do
            expect(response).to have_http_status(401)
          end
        end

        context 'with `offset`' do
          let(:search_params) { { q: 'test1', offset: 1 } }

          it 'returns http unauthorized' do
            expect(response).to have_http_status(401)
          end
        end
      end
    end
  end
end
