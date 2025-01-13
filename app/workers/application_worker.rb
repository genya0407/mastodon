# frozen_string_literal: true

class ApplicationWorker < ActiveJob::Base # rubocop:disable Rails/ApplicationJob
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
  retry_on StandardError

  around_perform do |_job, block|
    Rails.logger.tagged(ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] ? "traceID=#{OpenTelemetry::Trace.current_span.context.hex_trace_id}" : nil) do
      Rails.logger.tagged(ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] ? "spanID=#{OpenTelemetry::Trace.current_span.context.hex_span_id}" : nil) do
        Mastodon::SidekiqMiddleware.new.call(&block)
      end
    end
  end

  def self.push_bulk(elems, limit: 10_000)
    elems.each_slice(limit).map do |elems_batch|
      jobs = elems_batch.map do |elem|
        new(*yield(elem))
      end
      ActiveJob.perform_all_later(jobs)
    end
  end
end
