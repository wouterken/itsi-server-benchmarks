require_relative 'lib/util'
require_relative 'lib/benchmark_case'
require_relative 'servers'
require 'etc'
require 'debug'
require 'json'
require 'fileutils'
require 'open3'
require 'socket'
require 'timeout'
require 'time'
require 'paint'
require 'uri'

$LOAD_PATH.unshift(File.dirname(__FILE__))
$interrupt_signal = Queue.new

trap('INT') do
  exit(0) if $interrupt_signal.length > 0
  puts "\n[DEBUG] Caught Ctrl+C. Pausing before next iteration. Press again to exit."
  $interrupt_signal << true
end

def interrupted?
  $interrupt_signal.pop(true)
rescue StandardError
  false
end

def run_rack_bench
  filters = ARGV.map(&Regexp.method(:new))

  Dir.glob('test_cases/*/*.rb').each do |path|
    test_name = File.basename(path, '.rb')
    begin
      src = IO.read(path).strip
      next if src.empty?

      test_case = BenchmarkCase.new(test_name)
      test_case.instance_eval(src)

      if test_case.grpc? && !system('which ghz > /dev/null')
        puts Paint['Skipping gRPC test because exec `ghz` not found', :yellow]
        next
      elsif !system('which oha > /dev/null')
        puts Paint['Skipping HTTP test because exec `oha` not found', :yellow]
        next
      end

      Server.each do |server|
        next if filters.any? { |filter| !(filter =~ server.name.to_s || filter =~ test_name.to_s) }

        if !ENV['RACK_BENCH_OVERWRITE_RESULTS'] && result_exists?(test_case, server.name.to_s)
          puts "Results already exist for #{test_name}/#{server.name}"
          next
        end

        results = Array(test_case.threads).product(Array(test_case.workers),
                                                   [true, false]).map do |threads, workers, http2|
          next unless server.exec_found?
          next unless test_case.requires.all? { |r| server.supports?(r) }
          next if threads > 1 && !server.supports?(:threads)
          next if workers > 1 && !server.supports?(:processes)
          next if http2 && !server.supports?(:http2)
          next if !http2 && test_case.grpc?

          server_config_file_path = File.join(File.dirname(path), 'server_configurations', "#{server.name}.rb")
          unless File.exist?(server_config_file_path)
            server_config_file_path = "server_configurations/#{server.name}.rb"
          end

          run_benchmark(test_name, test_case, server_config_file_path, server, threads: threads, workers: workers,
                                                                               http2: http2)
        end.flatten.compact

        save_result(results, test_case, server.name.to_s) if results.any?
      rescue StandardError => e
        puts "Error during test case #{path}. #{e}"
        puts e.backtrace
      end
    end
  end
end

def serve
  filters = ARGV.tap(&:shift).map(&Regexp.method(:new))
  Dir.glob('test_cases/*/*.rb').each do |path|
    test_name = File.basename(path, '.rb')
    src = IO.read(path).strip
    next if src.empty?

    test_case = BenchmarkCase.new(test_name)
    test_case.instance_eval(src)

    if test_case.grpc? && !system('which ghz > /dev/null')
      puts Paint['Skipping gRPC test because exec `ghz` not found', :yellow]
      next
    elsif !system('which oha > /dev/null')
      puts Paint['Skipping HTTP test because exec `oha` not found', :yellow]
      next
    end

    Server.each do |server|
      next if filters.any? { |filter| !(filter =~ server.name.to_s || filter =~ test_name.to_s) }

      Array(test_case.threads).product(Array(test_case.workers), [true, false]).each do |threads, workers, http2|
        next unless server.exec_found?
        next unless test_case.requires.all? { |r| server.supports?(r) }
        next if threads > 1 && !server.supports?(:threads)
        next if workers > 1 && !server.supports?(:processes)
        next if http2 && !server.supports?(:http2)
        next if !http2 && test_case.grpc?

        server_config_file_path = File.join(File.dirname(path), 'server_configurations', "#{server.name}.rb")
        server_config_file_path = "server_configurations/#{server.name}.rb" unless File.exist?(server_config_file_path)

        run_server(test_name, test_case, server_config_file_path, server, threads: threads, workers: workers)
        break
      end
    end
  end
end

def run_server(
  _test_name, test_case, server_config_file_path, server,
  threads:, workers:
)
  server.run!(server_config_file_path, test_case, threads, workers) do |((url, _, _))|
    puts "Server running. Test at #{url}"
    loop do
      sleep 1
      break if interrupted?
    end
  end
end

def run_benchmark(
  test_name, test_case, server_config_file_path, server,
  threads:, workers:, http2:
)
  server.run!(server_config_file_path, test_case, threads, workers) do |urls, method, data|
    puts Paint["\n=== Running #{test_name} on #{server.name}", :cyan, :bold]

    url = \
      if urls.length > 1 && !test_case.grpc?
        tempfile = Tempfile.new('urls')
        tempfile.write(urls.join("\n"))
        tempfile.flush # Ensure content is written
        "--urls-from-file #{tempfile.path}"
      else
        urls.first
      end

    warmup_cmd =
      if test_case.grpc?
        "ghz --duration-stop=ignore --cpus=2 -z #{test_case.warmup_duration}s -c50 --call #{test_case.call} --stream-call-count=5 -d #{data.strip} --insecure #{URI(url).host}:#{URI(url).port} --proto #{test_case.proto} -O json"
      else
        "oha --no-tui -z #{test_case.warmup_duration}s -c50 #{url} -m #{method} #{data ? %(-d "#{data}") : ''} --output-format json #{http2 ? '--http2 --insecure' : ''} #{http2 ? "-p #{test_case.parallel_requests}" : ''}" # rubocop:disable Layout/LineLength
      end

    test_command_sets = test_case.concurrency_levels.map do |level|
      [
        level,
        if test_case.grpc?
          "ghz --duration-stop=ignore --cpus=2 -z #{test_case.duration}s -c#{level} --call #{test_case.call} --stream-call-count=5 -d #{data.strip} --insecure #{URI(url).host}:#{URI(url).port} --proto #{test_case.proto} -O json" # rubocop:disable Layout/LineLength
        else
          "oha --no-tui -z #{test_case.duration}s -c#{http2 ? (level / test_case.parallel_requests) : level} #{url} -m #{method} #{data ? %(-d "#{data}") : ''} --output-format json #{http2 ? '--http2 --insecure' : ''} #{http2 ? "-p #{test_case.parallel_requests}" : ''}" # rubocop:disable Layout/LineLength
        end
      ]
    end

    puts Paint["\nWarming up with:", :yellow, :bold]
    puts Paint[warmup_cmd, :yellow]
    `#{warmup_cmd}`

    test_command_sets.map do |concurrency, cmd| # rubocop:disable Metrics/BlockLength
      puts Paint["\n[#{test_case.name}] #{server.name}(#{workers}x#{threads}). Concurrency #{concurrency}. #{http2 ? 'HTTP/2.0' : 'HTTP/1.1'}",
                 :blue, :bold]
      puts Paint[cmd, :blue]
      result_json = JSON.parse(`#{cmd}`)
      result_output = \
        if test_case.grpc?
          success_rate = begin
            (result_json['statusCodeDistribution']&.[]('OK')&./ result_json['count'].to_f).round(4)
          rescue StandardError
            0
          end

          gross_rps = result_json['rps'].round(4)
          failure_rate = (1 - success_rate)
          net_rps = (gross_rps * (1 - failure_rate)).round(2)
          failure = failure_rate.*(100.0).round(2)

          error_distribution = result_json['errorDistribution']

          if failure.positive? && error_distribution
            puts Paint['• Error breakdown:', :red, :bold]
            max_key_length = error_distribution.keys.map(&:length).max
            error_distribution.each do |err, count|
              padded_key = err.ljust(max_key_length)
              puts Paint["  #{padded_key} : #{count}", :red]
            end
          end

          puts Paint % ['RPS: %{rps}. Errors: %{failure}%', :bold, :cyan, # rubocop:disable Style/FormatStringToken,Style/FormatString
                        { rps: [net_rps.to_s, :green], failure: [failure, failure.positive? ? :red : :green] }]
          {
            'successRate' => success_rate,
            'total' => result_json['count'],
            'slowest' => (result_json['slowest'] / 1_000_000.0).round(4),
            'fastest' => (result_json['fastest'] == Float::INFINITY ? 0.0 : result_json['fastest'] / 1_000_000.0).round(4),
            'average' => (result_json['average'] / 1_000_000.0).round(4),
            'requestsPerSec' => net_rps,
            'grossRequestsPerSec' => gross_rps,
            'errorDistribution' => error_distribution,
            'p95_latency' => result_json['latencyDistribution'].find do |ld|
              ld['percentage'] == 95
            end['latency'] / (1000.0**2)
          }
        else
          summary = result_json['summary']
          p95_latency     = result_json['latencyPercentiles']['p95']
          gross_rps       = summary['requestsPerSec'].to_f.round(2)
          success_rate    = summary['successRate'].to_f
          error_distribution = result_json['errorDistribution'] || {}

          # We interrupted requests mid-request due to our fixed timeout.
          # These interruptions are client initiated and we don't count this towards server errors.
          error_distribution.delete('aborted due to deadline')

          # Calculate total successful and failed responses based on status codes
          status_codes = result_json['statusCodeDistribution']
          success_codes = status_codes.select { |code, _| code =~ /^[123]/ }.values.sum.to_f
          error_codes   = status_codes.select do |code, _|
            code =~ /^[45]/ || code == 'error'
          end.values.sum.to_f
          total_codes = success_codes + error_codes

          # Avoid division by zero
          adjusted_success_rate = total_codes.positive? ? (success_codes / total_codes) : 0.0
          effective_success_rate = success_rate * adjusted_success_rate

          failure_rate = 1 - effective_success_rate
          net_rps = (success_codes / test_case.duration.to_f).round(2)
          failure = (failure_rate * 100).round(2)

          puts Paint % ['RPS: %{rps}. Errors: %{failure}%', :bold, :cyan, { # rubocop:disable Style/FormatStringToken,Style/FormatString
            rps: [net_rps.to_s, :green],
            failure: [failure, failure.positive? ? :red : :green]
          }]

          # Error breakdown
          if failure.positive? && error_distribution
            puts Paint['• Error breakdown:', :red, :bold]
            max_key_length = error_distribution.keys.map(&:length).max
            error_distribution.each do |err, count|
              puts Paint["  #{err.ljust(max_key_length)} : #{count}", :red]
            end
          end

          # Update and return summary
          summary.merge!(
            'errorDistribution' => result_json['errorDistribution'],
            'requestsPerSec' => net_rps,
            'grossRequestsPerSec' => gross_rps,
            'p95_latency' => p95_latency
          )

          summary.transform_values! { |v| v.is_a?(Numeric) ? v.round(2) : v }
          summary
        end
      binding.b if interrupted? # rubocop:disable Lint/Debugger
      {
        server: server.name,
        version: server.version,
        test_case: test_name,
        threads: threads,
        workers: workers,
        http2: http2,
        concurrency: concurrency,
        **(workers == 1 ? { rss_mb: (server.rss / (1024.0 * 1024.0)).round(2) } : {}),
        results: result_output,
        timestamp: Time.now.utc.iso8601
      }
    end
  end
end

def cpu_label
  uname, = Open3.capture2('uname -m')
  arch = uname.strip

  model = \
    case RUBY_PLATFORM
    when /darwin/
      output, = Open3.capture2('sysctl -n machdep.cpu.brand_string')
      output.strip
    when /linux/
      model_name = File.read('/proc/cpuinfo')[/^model name\s+:\s+(.+)$/, 1]
      model_name || arch
    else
      arch
    end

  model.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/^_|_+$/, '')
end

def save_result(result, test_case, server_name)
  path_prefix = File.join('results', cpu_label, test_case.group.to_s, test_case.name)
  FileUtils.mkdir_p(path_prefix)
  path = File.join(path_prefix, "#{server_name}.json")
  IO.write(path, JSON.pretty_generate(result, allow_nan: true))
end

def result_exists?(test_case, server_name)
  path_prefix = File.join('results', cpu_label, test_case.group.to_s, test_case.name)
  FileUtils.mkdir_p(path_prefix)
  File.exist? File.join(path_prefix, "#{server_name}.json")
end

case ARGV.first
when 'serve' then serve
else run_rack_bench
end
