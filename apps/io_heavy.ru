# frozen_string_literal: true

require 'json'
require 'active_record'
require 'net/http'
require 'tmpdir'

($db_connection_mux ||= Mutex.new).synchronize do
  next if defined? $io_party_initialized
  $io_party_initialized = true
  tmp_db_dir  = Dir.mktmpdir('io_party_db')
  tmp_db_file = File.join(tmp_db_dir, 'test.sqlite3')

  ActiveRecord::Base.establish_connection(
    adapter: 'sqlite3',
    database: tmp_db_file,
    checkout_timeout: 0.5
  )

  ActiveRecord::Schema.define do
    create_table :posts do |t|
      t.string :name
      t.text   :body
      t.timestamps
    end
  end

  ActiveRecord::Base.connection_handler.clear_active_connections!

  at_exit do
    ActiveRecord::Base.connection_pool.disconnect!
    FileUtils.rm_f(tmp_db_file)
    begin
      Dir.rmdir(tmp_db_dir)
    rescue StandardError
      nil
    end
  end

end


class Post < ActiveRecord::Base; end

run(
  proc do |_|

    begin
      post =  ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.execute('SELECT * FROM posts;')
        Post.find_or_create_by(name: 'Hello World', body: 'I have created a test post')
      end
      sleep 0.0001

      queue = Queue.new
      Thread.new do
        sleep 0.0001
        queue.push('done')
      end.join
      queue.pop

      t = Thread.new do
        sleep 0.0001
        queue.pop
      end

      queue.push('done')
      t.join

      ActiveRecord::Base.connection_pool.with_connection do
        post.update(name: 'Updated World', body: 'I have now updated the test post')
      end
      [200, { 'content-type' => 'text/plain'}, [post.to_json]]
    rescue StandardError => e
      [400, {}, ["bad things #{e}"]]
    end
  end
)
