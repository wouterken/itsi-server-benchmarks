# Server Benchmark Suite

A comprehensive performance benchmarking suite for Ruby Rack servers, gRPC servers, static file servers, and reverse proxies. This benchmark suite is designed to fairly evaluate server performance across diverse workloads and hardware configurations.

**Part of the [Itsi](https://itsi.fyi) project** - a high-performance web server, reverse proxy, and API gateway for Ruby applications.

## Purpose

This benchmark suite aims to provide transparent, reproducible performance comparisons across the Ruby web server ecosystem. It tests realistic workloads on varied hardware to help developers make informed decisions about server selection based on their specific use cases.

## Live Results

Interactive benchmark results and analysis are available at: **https://itsi.fyi/benchmarks**

## What's Tested

### Rack Servers
- **Itsi** - High-performance native server with async I/O
- **Puma** - Popular production Ruby server
- **Falcon** - Async Ruby server with fiber scheduler
- **Unicorn** - Process-based Ruby server
- **Iodine** - Native Ruby server with async capabilities
- **Agoo** - High-performance native server

### Reverse Proxies & Static Servers
- **Nginx** - Industry-standard reverse proxy
- **Caddy** - Modern HTTP/2 server with automatic HTTPS
- **H2O** - Optimized HTTP/2 server
- **Thruster** - HTTP/2 proxy for Ruby apps

### gRPC Servers
- **grpc-ruby** - Standard Ruby gRPC server implementation
- **Itsi gRPC** - High-performance gRPC with fiber scheduler support

## Test Categories

### Throughput Tests
- **empty_response** - Minimal overhead baseline
- **hello_world** - Simple string response
- **response_size_*** - Various response body sizes

### I/O & Concurrency
- **io_heavy** - Database and file I/O simulation
- **nonblocking_*_delay** - Async I/O patterns
- **chunked** - Streaming response handling

### CPU-Intensive
- **cpu_heavy** - Computational workloads
- **framework** - Full framework overhead (Sinatra)

### Static File Serving
- **static_small/large** - File serving performance
- **static_dynamic_mixed** - Realistic mixed workloads

### Streaming & Advanced Features
- **streaming_response** - HTTP streaming capabilities
- **full_hijack** - Low-level connection hijacking

### gRPC
- **echo_stream** - Bidirectional streaming
- **process_payment** - Unary RPC calls
- **echo_collect** - Client streaming

- **Apple M1 Pro** (6P+2E cores, ARM64) - Modern laptop performance
- **AMD Ryzen 5600** (6C/12T, AMD64) - High-end desktop
- **Intel N97** (4C, AMD64) - Entry-level/edge computing

## Getting Started

### Prerequisites

1. **Ruby** (3.0+) - [Installation Guide](https://www.ruby-lang.org/en/documentation/installation/)

2. **Build Tools** (Linux only):
   ```bash
   # Ubuntu/Debian
   apt-get install build-essential libclang-dev
   
   # RHEL/CentOS
   yum groupinstall "Development Tools"
   yum install clang-devel
   ```

3. **Reverse Proxies & Static Servers** (for proxy benchmark tests):
   - **Nginx**: [Installation Guide](https://nginx.org/en/docs/install.html)
   - **Caddy**: [Installation Guide](https://caddyserver.com/docs/install)
   - **H2O**: [Installation Guide](https://h2o.examp1e.net/install.html)

4. **Benchmark Tools**:
   ```bash
   # HTTP benchmarking
   cargo install oha
   
   # gRPC benchmarking (for gRPC tests)
   go install github.com/bojand/ghz/cmd/ghz@latest
   ```

### Installation

```bash
git clone https://github.com/wouterken/itsi-server-benchmarks
cd benchmarks
bundle install
```

### Running Benchmarks

**Run all benchmarks:**
```bash
bundle exec ruby rack_bench.rb
```

**Run specific test patterns:**
```bash
# Only throughput tests
bundle exec ruby rack_bench.rb throughput

# Only gRPC tests
bundle exec ruby rack_bench.rb grpc

# Specific test case
bundle exec ruby rack_bench.rb hello_world
```

**Interrupt handling:** Press Ctrl+C once to pause between iterations, twice to exit immediately.

## Debugging

To debug a benchmark configuration, you can use the `rack_bench.rb serve` command to start a server in its benchmark configuration, without actually running the load test.

E.g.
```bash
bundle exec ruby rack_bench.rb serve hello_world
```

## Benchmark Parameters
The following environment variables can be used to configure the benchmark:
* RACK_BENCH_WARMUP_DURATION_SECONDS (Default 1s)
* RACK_BENCH_DURATION_SECONDS (Default 3s)
* RACK_BENCH_THREADS (Default 1,5,10,20)
* RACK_BENCH_WORKERS (Default 1,2, Number of Processors)
* RACK_BENCH_CONCURRENCY_LEVELS (Default, 10, 50, 100, 250)

##  Project Structure

```
benchmarks/
├── rack_bench.rb              # Main benchmark runner
├── grpc_server.rb            # Standalone gRPC server
├── servers.rb                # Server configurations
├── lib/                      # Core benchmark framework
├── test_cases/               # Test case definitions
│   ├── throughput/           # Basic performance tests
│   ├── grpc/                # gRPC-specific tests
│   ├── static_file/         # File serving tests
│   ├── nonblocking/         # Async I/O tests
│   ├── cpu_heavy/           # CPU-intensive tests
│   └── ...
├── apps/                     # Rack applications & test data
│   ├── *.ru                 # Rack config files
│   ├── echo_service/        # gRPC service definitions
│   └── public/              # Static test files
├── server_configurations/    # Server-specific configs
└── results/                 # Benchmark output data
```

## 🔧 Configuration

### Test Case Format

Test cases are Ruby files defining benchmark parameters:

```ruby
# Basic HTTP test
app File.open('apps/hello_world.ru')
concurrency_levels([10, 50, 100])
threads [1, 4]
workers [1]

# gRPC test
proto "apps/echo_service/echo.proto"
call "echo.EchoService/EchoStream"
requires %i[grpc]
nonblocking true
```

### Server Configuration

Servers are defined in `servers.rb` with their capabilities and command templates:

```ruby
Server(
  :puma,
  '%<base>s -b tcp://%<host>s:%<port>s %<app_path>s -w %<workers>s -t %<threads>s',
  supports: %i[threads processes streaming_body ruby]
)
```

## Important Disclaimers

## Contributing

Contributions to improve benchmark accuracy and coverage are welcome:

1. **Configuration improvements**: PRs to optimize server configurations
2. **New test cases**: Additional realistic workload scenarios
3. **Bug fixes**: Corrections to benchmark methodology
4. **Documentation**: Clarifications and additional context

All benchmark source code is open for review and reproduction.

**For detailed analysis and interactive results**: https://itsi.fyi/benchmarks

**Itsi Documentation**: https://itsi.fyi
