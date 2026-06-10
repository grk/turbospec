module Turbospec
  class ResultSerializer
    def self.serialize(example, index)
      {
        type: "result",
        index: index,
        status: example.execution_result.status.to_s,
        id: example.id,
        description: example.description,
        file_path: example.file_path,
        line_number: example.location.split(':').last.to_i,
        execution_result: serialize_execution_result(example.execution_result)
      }
    end

    def self.deserialize(data, example)
      res = example.execution_result
      res.status = data["status"].to_sym
      res.run_time = data["execution_result"]["run_time"]
      res.pending_message = data["execution_result"]["pending_message"]

      if data["execution_result"]["exception"]
        res.exception = deserialize_exception(data["execution_result"]["exception"])
      end

      res
    end

    private

    def self.serialize_execution_result(result)
      data = {
        status: result.status,
        run_time: result.run_time,
        pending_message: result.pending_message
      }
      if result.exception
        data[:exception] = serialize_exception(result.exception)
      end
      data
    end

    def self.serialize_exception(exception)
      data = {
        class: exception.class.name,
        message: exception.message,
        backtrace: exception.backtrace
      }

      # Serialize the exception cause chain (for chained exceptions via `raise ... rescue`)
      if exception.cause
        data[:cause] = serialize_exception(exception.cause)
      end

      # Handle exceptions with multiple nested exceptions (aggregate_failures, multiple errors)
      # This covers both RSpec::Expectations::MultipleExpectationsNotMetError and
      # RSpec::Core::MultipleExceptionError (via InterfaceTag)
      if exception.respond_to?(:all_exceptions)
        data[:all_exceptions] = exception.all_exceptions.map { |e| serialize_exception(e) }
        data[:aggregation_metadata] = exception.aggregation_metadata if exception.respond_to?(:aggregation_metadata)
        data[:aggregation_block_label] = exception.aggregation_block_label if exception.respond_to?(:aggregation_block_label)
      end

      data
    end

    def self.deserialize_exception(ex_data)
      class_name = ex_data["class"]

      # Handle exceptions with multiple nested exceptions
      if ex_data["all_exceptions"]
        return deserialize_multiple_exception_error(ex_data)
      end

      # Deserialize the cause chain first (if present)
      cause = ex_data["cause"] ? deserialize_exception(ex_data["cause"]) : nil

      begin
        klass = Object.const_get(class_name)
      rescue NameError
        warn "Unknown exception class: #{class_name}, using RuntimeError"
        klass = RuntimeError
      end

      # Use ExceptionWithCause wrapper if there's a cause, otherwise create normally
      if cause
        ex = ExceptionWithCause.new(klass, ex_data["message"], ex_data["backtrace"], cause)
      else
        ex =
          begin
            klass.new(ex_data["message"])
          rescue StandardError
            # Custom constructors (e.g. required keyword arguments) can't be
            # rebuilt from a message string; fall back to the wrapper, which
            # fakes the original class for display.
            ExceptionWithCause.new(klass, ex_data["message"], ex_data["backtrace"], nil)
          end
        ex.set_backtrace(ex_data["backtrace"])
      end

      ex
    end

    def self.deserialize_multiple_exception_error(ex_data)
      # Deserialize child exceptions
      child_exceptions = (ex_data["all_exceptions"] || []).map { |child_data| deserialize_exception(child_data) }

      # Build aggregation metadata
      aggregation_metadata = symbolize_keys(ex_data["aggregation_metadata"] || {})
      aggregation_block_label = ex_data["aggregation_block_label"]

      # Create a wrapper that provides the interface RSpec's formatter expects
      MultipleExceptionsWrapper.new(
        ex_data["message"],
        ex_data["backtrace"],
        child_exceptions,
        aggregation_metadata,
        aggregation_block_label
      )
    end

    def self.symbolize_keys(hash)
      return {} unless hash.is_a?(Hash)
      hash.transform_keys { |k| k.is_a?(String) ? k.to_sym : k }
    end

    # A wrapper class that preserves exception cause chains across process boundaries.
    # Ruby's Exception#cause is normally set automatically when raising during rescue,
    # but we need to reconstruct it from serialized data.
    class ExceptionWithCause < StandardError
      attr_reader :original_class

      def initialize(original_class, message, backtrace, cause)
        super(message)
        @original_class = original_class
        set_backtrace(backtrace)
        @cause = cause
      end

      def cause
        @cause
      end

      # Delegate class name to original for proper error display
      def class
        original_class
      end
    end

    # A wrapper class that provides the full interface that RSpec's ExceptionPresenter expects
    # for both MultipleExpectationsNotMetError and MultipleExceptionError.
    #
    # It includes RSpec::Core::MultipleExceptionError::InterfaceTag at runtime so that RSpec's
    # exception presenter recognizes it as a multiple exception error and formats
    # all nested exceptions properly.
    class MultipleExceptionsWrapper < StandardError
      attr_reader :all_exceptions, :aggregation_metadata, :aggregation_block_label

      def initialize(message, backtrace, all_exceptions, aggregation_metadata, aggregation_block_label)
        super(message)
        set_backtrace(backtrace)
        @all_exceptions = all_exceptions
        @aggregation_metadata = aggregation_metadata || {}
        @aggregation_block_label = aggregation_block_label

        # Include the InterfaceTag at runtime when RSpec is available
        if defined?(RSpec::Core::MultipleExceptionError::InterfaceTag)
          singleton_class.include(RSpec::Core::MultipleExceptionError::InterfaceTag)
        end

        # Separate failures from other errors based on RSpec convention
        @failures = []
        @other_errors = []
        @all_exceptions.each do |ex|
          next if defined?(RSpec::Core::Pending::PendingExampleFixedError) &&
                  ex.is_a?(RSpec::Core::Pending::PendingExampleFixedError)

          if ex.class.name =~ /RSpec/
            @failures << ex
          else
            @other_errors << ex
          end
        end
      end

      # RSpec checks for these methods to determine failure types
      def failures
        @failures
      end

      def other_errors
        @other_errors
      end

      def exception_count_description
        failure_count = failures.size
        error_count = other_errors.size

        parts = []
        parts << "#{failure_count} failure#{failure_count == 1 ? '' : 's'}" if failure_count > 0
        parts << "#{error_count} error#{error_count == 1 ? '' : 's'}" if error_count > 0
        parts.join(" and ")
      end

      def summary
        "Got #{exception_count_description}"
      end

      # The InterfaceTag module expects an add method, provide a no-op since we're read-only
      def add(exception)
        # No-op for deserialized exceptions
      end
    end
  end
end
