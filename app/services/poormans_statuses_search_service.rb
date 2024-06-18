# frozen_string_literal: true

class PoormansStatusesSearchService < BaseService
  def self.enabled?
    true
  end

  def call(query, account = nil, options = {})
    @query   = query&.strip
    @account = account
    @options = options
    @limit   = options[:limit].to_i
    @offset  = options[:offset].to_i

    status_search_results
  end

  private

  def status_search_results
    results = @query.split(/[ 　]/).reduce(
      Status
        .where(
          {
            account_id: @options[:account_id],
            id: (@options[:min_id]&.to_i)..(@options[:max_id]&.to_i),
          }.compact
        )
    ) do |relation, word|
      relation.where('text LIKE ?', "%#{Status.sanitize_sql_like(word)}%")
    end.order(id: :desc).limit(@limit).offset(@offset)

    account_ids         = results.map(&:account_id)
    account_domains     = results.map(&:account_domain)
    preloaded_relations = @account.relations_map(account_ids, account_domains)

    results.reject { |status| StatusFilter.new(status, @account, preloaded_relations).filtered? }
  end
end
