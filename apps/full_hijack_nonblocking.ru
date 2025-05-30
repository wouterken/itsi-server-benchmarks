
def hijack_connection(io) # rubocop:disable Metrics/MethodLength
  @approach ||= Fiber.scheduler ? Fiber.method(:schedule) : Thread.method(:new)
  @approach.call do
    io.write "HTTP/1.1 200 OK\r\n" \
      "Content-Type: text/plain\r\n" \
      "Transfer-Encoding: chunked\r\n" \
      "\r\n"

    message = "Hello from full hijack! #{Thread.current}\n"
    io.write "#{message.bytesize.to_s(16)}\r\n" \
     "#{message}\r\n" \
     "0\r\n\r\n"

    io.close
  end
end

run Proc.new { |env|
  hijack_connection(env['rack.hijack'].call) if env['rack.hijack']

  [-1, {}, []]
}
