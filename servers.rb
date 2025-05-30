# frozen_string_literal: true

require_relative 'lib/server'

# Stand-alone Rack Servers
Server(
  :itsi,
  '%<base>s -C %<config>s -b %<scheme>s://%<host>s:%<port>s --rackup_file=%<app_path>s -w %<workers>s -t %<threads>s %<scheduler_toggle>s',
  supports: %i[http2 threads processes streaming_body full_hijack static file_server ruby grpc],
  scheduler_toggle: ->(test_case, _args) { test_case.nonblocking ? '-f' : '' }
)

Server(
  :puma,
  '%<base>s %<config>s-b tcp://%<host>s:%<port>s?backlog=64 %<app_path>s -w %<workers>s -t %<threads>s:%<threads>s',
  supports: %i[threads processes streaming_body full_hijack static file_server ruby],
  config: ->(_, args) { File.exist?(args[:config]) ? "-C #{args[:config]} " : '' }
)

Server(
  :falcon,
  '%<base>s -b %<scheme>s://%<host>s:%<port>s -c %<app_path>s --hybrid --forks %<workers>s --threads %<threads>s',
  supports: %i[http2 threads processes streaming_body full_hijack static file_server ruby]
)

Server(
  :unicorn,
  'UNICORN_WORKERS=%<workers>s %<base>s %<config>s -l %<host>s:%<port>s %<app_path>s',
  supports: %i[processes static file_server ruby],
  config: ->(_, args) { File.exist?(args[:config]) ? "-c #{args[:config]} " : '' }
)

Server(
  :iodine,
  '%<base>s -p %<port>s %<app_path>s -w %<workers>s -t %<threads>s %<www>s',
  # Iodine buffers the entire request body before returning.
  supports: %i[threads processes static file_server ruby],
  www: ->(test_case, _args) { test_case.static_files_root ? "-www #{test_case.static_files_root}" : '' }
)

Server(
  :agoo,
  '%<base>s -p %<port>s %<app_path>s -w %<workers>s -t %<threads>s %<www>s',
  # Agoo supposedly supports threading, but in local tests it spins up only a single thread
  # regardless of the argument given for `-t`
  chdir: 'apps',
  supports: %i[processes full_hijack static file_server ruby],
  www: ->(test_case, _args) { test_case.static_files_root ? "-d #{test_case.static_files_root}" : '' },
  app_path: ->(_test_case, args) { args[:app_path].gsub('apps/', '') }
)

# Puma + Reverse Proxy (We could do this for any Rack server, but focus on just Puma+Proxy for now as the most common
# production combination).
# We don't run file server tests here for these combo servers because
# we already test the reverse proxies as file-servers independently
Server(
  :puma__nginx,
  '%<base>s %<config>s-b tcp://%<host>s:%<port>s?backlog=32 %<app_path>s -w %<workers>s -t %<threads>s:%<threads>s',
  proxy_cmd: "nginx -p \"#{Dir.pwd}\" -c %<proxy_config_file>s -g \"daemon off;\"",
  www: ->(test_case, _args) { test_case.static_files_root ? "-d #{test_case.static_files_root}" : '' },
  supports: %i[http2 threads processes streaming_body full_hijack static ruby],
  config: ->(_, args) { File.exist?(args[:config]) ? "-C #{args[:config]} " : '' },
  proxy_config_file: lambda { |_, args|
    temp_config = Tempfile.create(['nginx', '.conf'])
    temp_config.write(IO.read('server_configurations/proxies/nginx.conf') % args)
    temp_config.flush
    temp_config.path
  }
)

Server(
  :puma__thrust,
  'TARGET_PORT=%<backend_port>s HTTP_PORT=%<port>s bundle exec thrust puma %<config>s -b tcp://%<host>s:%<backend_port>s %<app_path>s -w %<workers>s -t %<threads>s:%<threads>s',
  supports: %i[threads processes streaming_body full_hijack static ruby],
  backend_port: ->(_, _) { free_port },
  config: ->(_, args) { File.exist?(args[:config]) ? "-C #{args[:config]} " : '' }
)

Server(
  :puma__itsi,
  '%<base>s %<config>s-b tcp://%<host>s:%<port>s?backlog=32 %<app_path>s -w %<workers>s -t %<threads>s:%<threads>s',
  proxy_cmd: 'itsi -C %<proxy_config_file>s',
  www: ->(test_case, _args) { test_case.static_files_root ? "-d #{test_case.static_files_root}" : '' },
  supports: %i[http2 http1 threads processes streaming_body full_hijack static ruby],
  config: ->(_, args) { File.exist?(args[:config]) ? "-C #{args[:config]} " : '' },
  proxy_config_file: lambda { |_, args|
    temp_config = Tempfile.create(['itsi', '.rb'])
    temp_config.write(IO.read('server_configurations/proxies/itsi.conf') % args)
    temp_config.flush
    temp_config.path
  }
)

Server(
  :puma__caddy,
  '%<base>s %<config>s-b tcp://%<host>s:%<port>s?backlog=32 %<app_path>s -w %<workers>s -t %<threads>s:%<threads>s',
  proxy_cmd: 'GOMAXPROCS=%<workers>s caddy run --config %<proxy_config_file>s',
  www: ->(test_case, _args) { test_case.static_files_root ? "-d #{test_case.static_files_root}" : '' },
  supports: %i[http2 threads processes streaming_body full_hijack static ruby],
  config: ->(_, args) { File.exist?(args[:config]) ? "-C #{args[:config]} " : '' },
  proxy_config_file: lambda { |_, args|
    temp_config = Tempfile.create(['caddy', '.conf'])
    temp_config.write(IO.read('server_configurations/proxies/caddy.conf') % args)
    temp_config.flush
    temp_config.path
  }
)

Server(
  :puma__h2o,
  '%<base>s %<config>s-b tcp://%<host>s:%<port>s?backlog=32 %<app_path>s -w %<workers>s -t %<threads>s:%<threads>s',
  proxy_cmd: 'h2o -c %<proxy_config_file>s',
  www: ->(test_case, _args) { test_case.static_files_root ? "-d #{test_case.static_files_root}" : '' },
  supports: %i[http2 threads processes streaming_body full_hijack static ruby],
  config: ->(_, args) { File.exist?(args[:config]) ? "-C #{args[:config]} " : '' },
  proxy_config_file: lambda { |_, args|
    temp_config = Tempfile.create(['h2o', '.conf'])
    temp_config.write(IO.read('server_configurations/proxies/h2o.conf') % args)
    temp_config.flush
    temp_config.path
  }
)

# Static web-servers for simple file-serving tests
Server(
  :nginx,
  "nginx -p \"#{Dir.pwd}\" -c %<config_file>s -g 'daemon off;'",
  supports: %i[static file_server processes http2],
  www: ->(test_case, _args) { test_case.static_files_root ? "-d #{test_case.static_files_root}" : '' },
  config_file: lambda { |_, args|
    temp_config = Tempfile.create(['nginx', '.conf'])
    temp_config.write(IO.read('server_configurations/nginx.conf') % args)
    temp_config.flush
    temp_config.path
  }
)

Server(
  :caddy,
  'GOMAXPROCS=%<workers>s caddy run --config %<config_file>s',
  supports: %i[static file_server processes http2],
  config_file: lambda { |_, args|
    temp_config = Tempfile.create(['caddy', '.conf'])
    temp_config.write(IO.read('server_configurations/caddy.conf') % args)
    temp_config.flush
    temp_config.path
  }
)

Server(
  :h2o,
  'h2o -c %<config_file>s',
  supports: %i[static file_server processes http2],
  config_file: lambda { |_, args|
    temp_config = Tempfile.create(['h2o', '.conf'])
    temp_config.write(IO.read('server_configurations/h2o.conf') % args)
    temp_config.flush
    temp_config.path
  }
)

# Compare to a simple gRPC server using the official `grpc` gem.
Server(
  :"grpc_server.rb",
  'bundle exec ruby ./grpc_server.rb',
  supports: %i[grpc threads http2]
)
