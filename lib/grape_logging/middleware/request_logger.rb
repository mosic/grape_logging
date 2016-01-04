require 'thread'
require 'logger'

module GrapeLogging
  module Middleware
    class RequestLogger

      def initialize(app, options = {})
        @app = app
        @logger = options[:logger] || Logger.new(STDOUT)
        @obfuscated_params = options[:obfuscated_params] || []
        @ignored_methods = options[:ignored_methods] || []

        subscribe_to_active_record if defined? ActiveRecord
      end

      def call(env)
        request = ::Rack::Request.new(env)

        init_db_runtime

        start_time = Time.now

        response = @app.call(env)

        stop_time = Time.now

        total_runtime = calculate_runtime(start_time, stop_time)

        unless @ignored_methods.include? request.request_method
          log(request, response, total_runtime)
        end

        clear_db_runtime

        response
      end

      protected

      def subscribe_to_active_record
        ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          increase_db_runtime(event.duration)
        end
      end

      def log(request, response, total_runtime)
        @logger.info(
          path: request.path,
          params: obfuscate_parameters(request.params),
          method: request.request_method,
          total: format_runtime(total_runtime),
          db: format_runtime(db_runtime),
          status: response.is_a?(Rack::Response) ? response.status : response[0]
        )
      end

      def calculate_runtime(start_time, stop_time)
        (stop_time - start_time) * 1000
      end

      def format_runtime(time)
        time.round(2)
      end

      def init_db_runtime
        Thread.current[:db_runtime] = 0
      end

      def clear_db_runtime
        Thread.current[:db_runtime] = nil
      end

      def increase_db_runtime(time)
        Thread.current[:db_runtime] += time
      end

      def db_runtime
        Thread.current[:db_runtime]
      end

      def obfuscate_parameters(request_parameters)
        filtered_parameters = request_parameters.clone.to_hash
        sensitive_parameters.each do |param|
          filtered_parameters[param.to_s] = '***'
        end
        filtered_parameters
      end

      def sensitive_parameters
        @obfuscated_params
      end
    end
  end
end
