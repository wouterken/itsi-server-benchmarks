def wait_for_port(port, timeout: 5)
  Timeout.timeout(timeout) do
    loop do
      TCPSocket.new('127.0.0.1', port).close
      break
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      sleep 0.1
    end
  end
rescue Timeout::Error
  raise "Unable to connect to localhost:#{port}"
end


def free_port
  server = TCPServer.new("0.0.0.0", 0)
  port = server.addr[1]
  server.close
  port
end
