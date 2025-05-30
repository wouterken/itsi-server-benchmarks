path(['public/image.png', 'public/index.html', 'dynamic'])

static_files_root './apps'

requires %i[static ruby]

concurrency_levels([32, 64, 128, 256, 512])

threads [1, 4]

app File.open('apps/static.ru')

parallel_requests 8

group :static
