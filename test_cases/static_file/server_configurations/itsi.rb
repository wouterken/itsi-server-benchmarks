# First attempt to serve incoming requests as static assets,
# falling through to our rack-mapp on not-found.
static_assets root_dir: './apps', not_found_behavior: 'fallthrough', auto_index: true,
              auto_index: false,
              try_html_extension: true,
              max_file_size_in_memory: 1_048_576_000,
              max_files_in_memory: 100

# To make benchmarks fair. If we use too small a default, Itsi will start applying backpressure
# by returning 503s under heavy loads for distant queued requests to Ruby,
# causing an artificial increase in throughput
ruby_thread_request_backlog_size 100_000
