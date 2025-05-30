# Rack static handler. Fallback for servers that do not have built-in static asset serving.
# * Do have static asset serving: nginx, caddy, h2o, itsi, agoo, iodine
# * Don't have static asset serving: pume, falcon, unicorn
use Rack::Static,
    urls: ['/public'],
    root: File.expand_path('.', __dir__),
    index: 'index.html'

# Fast endpoint
run lambda { |env|
  [200, { 'Content-Type' => 'text/plain' }, ["Fast Endpoint: #{env['PATH_INFO']}"]]
}
