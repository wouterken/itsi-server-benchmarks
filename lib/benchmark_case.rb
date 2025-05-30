# lib/benchmark_case.rb
class BenchmarkCase
  require 'etc'

  # Give the server some time to warm up before we start measuring.
  RACK_BENCH_WARMUP_DURATION_SECONDS = ENV.fetch('RACK_BENCH_WARMUP_DURATION_SECONDS', 1).to_i

  # A default 3 is relatively low, but allows us to get through the entire test
  # suite quickly. For a more robust benchmark, this should be higher.
  RACK_BENCH_DURATION_SECONDS = ENV.fetch('RACK_BENCH_DURATION_SECONDS', 3).to_i

  RACK_BENCH_THREADS = ENV.fetch('RACK_BENCH_THREADS', '1, 5, 10, 20').to_s.split(',').map(&:to_i)
  RACK_BENCH_WORKERS = ENV.fetch('RACK_BENCH_WORKERS', "1, 2, #{::Etc.nprocessors}").to_s.split(',').map(&:to_i)
  RACK_BENCH_CONCURRENCY_LEVELS = ENV.fetch('RACK_BENCH_CONCURRENCY_LEVELS', '10, 50, 100, 250').to_s.split(',').map(&:to_i)

  %i[
    name description app method data path
    workers threads warmup_duration concurrency_levels
    duration https parallel_requests nonblocking
    requires use_yjit static_files_root grpc call proto
    group
  ].each do |accessor|
    define_method(accessor) do |value = self|
      if value.eql?(self)
        instance_variable_get("@#{accessor}")
      else
        instance_variable_set("@#{accessor}", value)
      end
    end
  end

  def initialize(name) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    @name = name
    @description = ''
    @method = 'GET'
    @data = nil
    @path = '/'
    @proto = ""
    @call = ""
    @workers = 1
    @group = "rack"
    @threads = RACK_BENCH_THREADS
    @workers = RACK_BENCH_WORKERS
    @concurrency_levels = RACK_BENCH_CONCURRENCY_LEVELS
    @duration = RACK_BENCH_DURATION_SECONDS
    @warmup_duration = RACK_BENCH_WARMUP_DURATION_SECONDS
    @static_files_root = nil
    @https = false
    @grpc = false
    @parallel_requests = 10
    @nonblocking = false
    @requires = %i[ruby]
    @use_yjit = true
    yield self if block_given?
  end

  def method_missing(name, *args, **kwargs, &blk)
    return super unless name.end_with?('?')

    @requires.include?(name[0...-1].to_sym)
  end

  def respond_to_missing?(name, include_private = false)
    @requires.include?(name[0...-1].to_sym) || super
  end
end
