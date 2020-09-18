# frozen_string_literal: true

module PrometheusExporter::Server
  class WebCollector < TypeCollector
    MAX_WEB_METRIC_AGE = 28800

    WEB_SUMS = {
      'duration_seconds' => 'Time spent in HTTP reqs in seconds.',
      'redis_duration_seconds' => 'Time spent in HTTP reqs in Redis, in seconds.',
      'sql_duration_seconds' => 'Time spent in HTTP reqs in SQL in seconds.',
      'queue_duration_seconds' => 'Time spent queueing the request in load balancer in seconds.',
    }.freeze

    attr_reader :web_metrics

    def initialize
      @web_metrics = []
    end

    def type
      'web'
    end

    def metrics
      return [] if web_metrics.length == 0

      metrics = {}

      web_metrics.map do |metric|
        labels = metric.fetch('labels', {})

        if (value = metric['requests_status'])
          counter = metrics['requests_total'] ||= PrometheusExporter::Metric::Counter.new(
            'http_requests_total',
            'Total HTTP requests from web app.',
          )
          counter.observe(1, labels.merge(status: value))
        end

        WEB_SUMS.map do |name, help|
          if (value = metric[name])
            sum = metrics[name] ||= PrometheusExporter::Metric::Summary.new("http_#{name}", help)
            sum.observe(value, labels)
          end
        end
      end

      metrics.values
    end

    def collect(obj)
      metrics = {}
      now = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)

      metrics['created_at'] = now
      metrics['labels'] = {
        controller: obj['controller'] || 'other',
        action: obj['action'] || 'other',
      }
      metrics['labels'].merge!(obj.fetch('custom_labels', {}))

      metrics['requests_status'] = obj['status']

      if timings = obj['timings']
        metrics['duration_seconds'] = timings['total_duration']

        if redis = timings['redis']
          metrics['redis_duration_seconds'] = redis['duration']
        end

        if sql = timings['sql']
          metrics['sql_duration_seconds'] = sql['duration']
        end
      end

      if queue_time = obj['queue_time']
        metrics['queue_duration_seconds'] = queue_time
      end

      web_metrics.delete_if { |metric| metric['created_at'] + MAX_WEB_METRIC_AGE < now }
      web_metrics << metrics
    end
  end
end
