workers 1

requires %i[grpc]

proto "apps/echo_service/echo.proto"

call "echo.EchoService/Echo"

data "{}"

nonblocking true

app File.open("apps/hello_world.ru")

group :grpc
