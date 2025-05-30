workers 1

requires %i[grpc]

proto "apps/echo_service/echo.proto"

call "echo.EchoService/ProcessPayment"

data <<~JSON
  '{
    "customer_id": "customer_1",
    "amount": {
      "currency_code": "USD",
      "units": 100,
      "nanos": 0
    },
    "payment_time": "2006-01-02T15:04:05Z"
  }'
JSON

nonblocking true

app File.open("apps/hello_world.ru")

group :grpc
