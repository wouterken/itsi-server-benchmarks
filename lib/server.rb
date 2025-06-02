# frozen_string_literal: true

require 'sys/proctable'
include Sys # rubocop:disable Style/MixinUsage
require 'shellwords'

def Server(...) = Server.new(...)

class Server # rubocop:disable Style/Documentation,Metrics/ClassLength
  attr_reader :name, :cmd_template, :proxy_cmd_template, :supports

  ALL = []

  def self.each(...)
    ALL.each(...)
  end

  CMD_TO_LIB_MAP = { 'thrust' => 'thruster' }.freeze

  def version
    @version ||= @name.to_s.split('__').map do |part|
      part = CMD_TO_LIB_MAP.fetch(part, part)
      case part.to_sym
      when :puma then `bundle exec puma --version 2>&1`
      when :itsi then `bundle exec itsi -v 2>&1`
      when :falcon then `bundle exec falcon -v 2>&1`
      when :unicorn then `bundle exec unicorn -v 2>&1`
      when :passenger then `bundle exec passenger -v 2>&1`
      when :nginx then `nginx -v 2>&1`
      when :caddy then "Caddy #{`caddy -v 2>&1`.split(' ').first}"
      when :h2o then `h2o -v | head -1`
      else
        begin
          tlm_name = part.capitalize
          require "#{part}/version"
          Kernel.instance_eval(%("#{tlm_name} \#{#{tlm_name}::VERSION}"), __FILE__, __LINE__)
        rescue Exception # rubocop:disable Lint/RescueException
          'Unknown'
        end
      end
    end.map(&:strip).join('+')
  end

  def initialize(name, cmd_template, supports: [], version_cmd: nil, **custom_args)
    @name = name
    @cmd_template = cmd_template
    @supports = supports
    @custom_args = custom_args
    @version_cmd = version_cmd
    @proxy_cmd_template = @custom_args.delete(:proxy_cmd)
    ALL << self
  end

  def supports?(feature)
    @supports.include?(feature)
  end

  def spawn_quietly(cmd, env = {}, timeout: 2, chdir: Dir.pwd) # rubocop:disable Metrics/AbcSize
    stderr_r, stderr_w = IO.pipe
    pid = Process.spawn(
      env, cmd,
      out: File::NULL,
      err: stderr_w,
      pgroup: true,
      chdir: chdir
    )

    stderr_w.close

    start_time = Time.now
    loop do
      result = Process.waitpid2(pid, Process::WNOHANG)
      if result
        _, status = result
        error = stderr_r.read

        unless status.success?
          warn "\n#{cmd.inspect} exited early with status #{status.exitstatus}"
          warn "STDERR:\n#{error}" unless error.empty?
        end
        return pid, status
      end

      break if (Time.now - start_time) > timeout

      sleep 0.1
    end

    Thread.new do
      until stderr_r.closed?
        stderr_r.read
        sleep 0.1
      end
      puts 'Exit flush'
    end

    [pid, nil] # process still running
  end

  def run!(server_config_file_path, test_case, threads, workers)
    port = free_port

    @builder_args = {
      base: "bundle exec #{@name.to_s.split('__').first}",
      config: server_config_file_path,
      scheme: test_case.https ? 'https' : 'http',
      host: '0.0.0.0',
      app_path: test_case.app&.path,
      workers: workers,
      threads: threads,
      www: test_case.static_files_root,
      port: port
    }

    proxy_port = \
      (@builder_args[:proxy_port] = free_port if @proxy_cmd_template)

    @builder_args.merge!(@custom_args.transform_values { |v| v.is_a?(Proc) ? v[test_case, @builder_args] : v })
    template_args = @builder_args.to_h.transform_keys(&:to_sym)

    proxy_cmd = proxy_cmd_template % template_args if proxy_cmd_template
    cmd       = cmd_template % template_args

    puts Paint["\nStarting server:", :green, :bold]
    puts Paint[cmd, :green]

    @proxy_pid = nil
    @pid = nil

    begin
      # Start the main server
      @pid, status = spawn_quietly(cmd, {
                                     'RUBY_YJIT_ENABLE' => "#{test_case.use_yjit}",
                                     'PORT' => port.to_s,
                                     'THREADS' => threads.to_s
                                   }, chdir: @builder_args.fetch(:chdir, Dir.pwd))

      # Start the proxy if needed
      if proxy_cmd
        puts Paint["\nStarting proxy:", :cyan, :bold]
        puts Paint[proxy_cmd, :cyan]

        @proxy_pid, proxy_status = spawn_quietly(proxy_cmd, { 'PORT' => proxy_port.to_s })
      end

      # Wait for both ports
      wait_for_port(port)
      wait_for_port(proxy_port) if @proxy_pid

      puts Paint["server pid: #{@pid}", :yellow]
      puts Paint["proxy pid: #{@proxy_pid}", :yellow] if @proxy_pid

      # Determine base port for requests
      base_port = @proxy_pid ? proxy_port : port

      paths = Array(test_case.path)
      methods = Array(test_case.method)
      data = Array(test_case.data)
      result = yield [
        Array(test_case.path).map { |p| "http://127.0.0.1:#{base_port}/#{p.gsub(%r{^/+}, '')}" },
        test_case.method,
        test_case.data
      ]
    rescue StandardError => e
      puts Paint["Server or proxy failed to start: #{e.message}. `#{cmd}`", :red, :bold]
      puts e.backtrace
      result = false
    end

    result
  rescue StandardError => e
    binding.b # rubocop:disable Lint/Debugger
  ensure
    stop!
  end

  def exec_found?
    return @exec_found if defined?(@exec_found)

    @exec_found = name.to_s.split('__').all? do |name|
      system("which #{name} > /dev/null") || system("ls #{name}")
    end
  end

  def rss
    @pid ? ProcTable.ps(pid: @pid).rss.to_i : 0
  rescue StandardError
    0
  end

  def try_signal(pid, signal)
    Process.kill(signal, pid)
  rescue Errno::ESRCH
  end

  def kill_process_tree(root_pid)
    children = `pgrep -P #{root_pid}`.split.map(&:to_i)
    children.each { |child| kill_process_tree(child) }
    Process.kill('TERM', root_pid)
  rescue Errno::ESRCH
  end

  def stop! # rubocop:disable Metrics/MethodLength
    # Ensure both processes are cleaned up
    [@proxy_pid, @pid].compact.each do |pid|
      kill_process_tree(pid)
      pgid = Process.getpgid(pid)
      try_signal(-pgid, 'TERM')
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      loop do
        _, status = Process.waitpid2(pid, Process::WNOHANG)
        break if status&.exited?

        try_signal(pid, 'TERM')

        if (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) > 1
          try_signal(-pgid, 'KILL')
          break
        end
        sleep 0.1
      end

      try_signal(pid, 'KILL')
    rescue Exception # rubocop:disable Lint/RescueException,Lint/SuppressedException
    end
    loop do
      Process.wait(-1, Process::WNOHANG)
    rescue Errno::ECHILD
      break
    end
  end
end
