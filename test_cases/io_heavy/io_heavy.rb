# frozen_string_literal: true

nonblocking true

app File.open('apps/io_heavy.ru')

group :rack
