# frozen_string_literal: true

module SidekiqAdapter
  def have_enqueued_sidekiq_job(*args)
    have_been_enqueued.with(*args)
  end
end
