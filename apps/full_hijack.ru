# You don't have to start a new thread for a hijacked connection, but it's common
# way to allow an arbitrary number of hijacked connections on a threaded blocking web-server.
def hijack_connection(io) # rubocop:disable Metrics/MethodLength
  Thread.new do
    begin
      io.write "HTTP/1.1 200 OK\r\n" \
              "Content-Type: text/plain\r\n" \
              "Transfer-Encoding: chunked\r\n" \
              "\r\n"

      message = "Hello from full hijack!\n"
      io.write "#{message.bytesize.to_s(16)}\r\n#{message}\r\n0\r\n\r\n"
    rescue => e
      warn "Hijack error: #{e.message}"
    ensure
      io.close unless io.closed?
    end
  end
end

run Proc.new { |env|
  hijack_connection(env['rack.hijack'].call) if env['rack.hijack']
  [200, { 'rack.hijack' => true }, []]
}
