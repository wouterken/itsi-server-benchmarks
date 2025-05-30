require 'sinatra/base'

# A minimal but complete Sinatra app
class MyApp < Sinatra::Base
  get '/get' do
    "Hello, world!"
  end

  post '/post' do
    "You posted: #{request.body.read}: #{Thread.current.object_id}"
  end
end

MyApp.protection = false
MyApp.host_authorization = {permitted_hosts: nil}

run MyApp
