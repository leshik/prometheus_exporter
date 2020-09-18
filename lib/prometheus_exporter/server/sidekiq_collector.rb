# frozen_string_literal: true

module PrometheusExporter::Server
  class SidekiqCollector < TypeCollector
    MAX_SIDEKIQ_METRIC_AGE = 28800

    SIDEKIQ_SUMS = {
      'job_duration_seconds' => 'Total time spent in sidekiq jobs.',
    }.freeze

    SIDEKIQ_COUNTERS = {
      'jobs_total' => 'Total number of sidekiq jobs executed.',
      'restarted_jobs_total' => 'Total number of sidekiq jobs that we restarted because of a sidekiq shutdown.',
      'failed_jobs_total' => 'Total number of failed sidekiq jobs.',
      'dead_jobs_total' => 'Total number of dead sidekiq jobs.',
    }.freeze

    attr_reader :sidekiq_metrics

    def initialize
      @sidekiq_metrics = []
    end

    def type
      'sidekiq'
    end

    def metrics
      return [] if sidekiq_metrics.length == 0

      metrics = {}

      sidekiq_metrics.map do |metric|
        labels = metric.fetch('labels', {})

        SIDEKIQ_SUMS.map do |name, help|
          if (value = metric[name])
            sum = metrics[name] ||= PrometheusExporter::Metric::Summary.new("sidekiq_#{name}", help)
            sum.observe(value, labels)
          end
        end

        SIDEKIQ_COUNTERS.map do |name, help|
          if (value = metric[name])
            counter = metrics[name] ||= PrometheusExporter::Metric::Counter.new("sidekiq_#{name}", help)
            counter.observe(value, labels)
          end
        end
      end

      metrics.values
    end

    def collect(obj)
      metrics = {}
      now = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)

      metrics['created_at'] = now
      metrics['labels'] = { job_name: obj['name'] }
      metrics['labels'].merge!(obj.fetch('custom_labels', {}))

      if obj['dead']
        metrics['dead_jobs_total'] = 1
      else
        metrics['job_duration_seconds'] = obj['duration']
        metrics['jobs_total'] = 1
        metrics['restarted_jobs_total'] = 1 if obj['shutdown']
        metrics['failed_jobs_total'] = 1 if !obj['success'] && !obj['shutdown']
      end

      sidekiq_metrics.delete_if { |metric| metric['created_at'] + MAX_SIDEKIQ_METRIC_AGE < now }
      sidekiq_metrics << metrics
    end
  end
end
