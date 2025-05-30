# frozen_string_literal: true

nonblocking true

app File.open('apps/cpu_heavy.ru')

group :rack
