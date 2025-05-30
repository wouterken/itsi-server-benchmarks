path 'public/image.png'

static_files_root './apps'

requires %i[static file_server]

threads [1]

concurrency_levels([32, 64, 128, 256, 512])

parallel_requests 16

app File.open('apps/static.ru')

group :static
