# frozen_string_literal: true

module PrometheusExporter::Server
  class WebCollector < TypeCollector
    MAX_WEB_METRIC_AGE = 28800

    def initialize
      @metrics = {}
      @history = {}
      @http_requests_total = nil
      @http_duration_seconds = nil
      @http_redis_duration_seconds = nil
      @http_sql_duration_seconds = nil
      @http_queue_duration_seconds = nil
    end

    def type
      'web'
    end

    def collect(obj)
      ensure_metrics
      observe(obj)
    end

    def metrics
      @metrics.values
    end

    protected

    def ensure_metrics
      unless @http_requests_total
        @metrics['http_requests_total'] = @http_requests_total = PrometheusExporter::Metric::Counter.new(
          'http_requests_total',
          'Total HTTP requests from web app.'
        )

        @metrics['http_duration_seconds'] = @http_duration_seconds = PrometheusExporter::Metric::Summary.new(
          'http_duration_seconds',
          'Time spent in HTTP reqs in seconds.'
        )

        @metrics['http_redis_duration_seconds'] = @http_redis_duration_seconds = PrometheusExporter::Metric::Summary.new(
          'http_redis_duration_seconds',
          'Time spent in HTTP reqs in Redis, in seconds.'
        )

        @metrics['http_sql_duration_seconds'] = @http_sql_duration_seconds = PrometheusExporter::Metric::Summary.new(
          'http_sql_duration_seconds',
          'Time spent in HTTP reqs in SQL in seconds.'
        )

        @metrics['http_queue_duration_seconds'] = @http_queue_duration_seconds = PrometheusExporter::Metric::Summary.new(
          'http_queue_duration_seconds',
          'Time spent queueing the request in load balancer in seconds.'
        )
      end
    end

    def observe(obj)
      now = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)

      labels = {
        controller: obj['controller'] || 'other',
        action: obj['action'] || 'other'
      }
      labels.merge!(obj.fetch('custom_labels', {}))

      @history[labels] = now

      @http_requests_total.observe(1, labels.merge(status: obj['status']))

      if timings = obj['timings']
        @http_duration_seconds.observe(timings['total_duration'], labels)

        if redis = timings['redis']
          @http_redis_duration_seconds.observe(redis['duration'], labels)
        end

        if sql = timings['sql']
          @http_sql_duration_seconds.observe(sql['duration'], labels)
        end
      end

      if queue_time = obj['queue_time']
        @http_queue_duration_seconds.observe(queue_time, labels)
      end

      @history.each_pair do |l, t|
        if t + MAX_WEB_METRIC_AGE < now
          @http_requests_total.remove(l.merge(status: obj['status']))
          @http_duration_seconds.remove(l)
          @http_redis_duration_seconds.remove(l)
          @http_sql_duration_seconds.remove(l)
          @http_queue_duration_seconds.remove(l)
          @history.delete(l)
        end
      end
    end
  end
end
