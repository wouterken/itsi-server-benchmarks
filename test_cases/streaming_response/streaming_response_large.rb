# frozen_string_literal: true

requires %i[streaming_body]

nonblocking true

app File.open('apps/streaming_response_large.ru')
