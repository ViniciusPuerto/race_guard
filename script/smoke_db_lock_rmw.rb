# frozen_string_literal: true

# End-to-end smoke: RMW detector (4.1) + lock awareness (4.2).
# From repo root (either works):
#   ruby script/smoke_db_lock_rmw.rb
#   bundle exec ruby -Ilib script/smoke_db_lock_rmw.rb

lib = File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'tmpdir'
require 'json'
require 'stringio'
require 'fileutils'
require 'active_record'
require 'sqlite3'
require 'race_guard'
require 'race_guard/active_record'

def smoke_fail!(message)
  warn message
  exit 1
end

def parse_rmw_lines(io)
  rows = io.string.lines.filter_map do |line|
    JSON.parse(line)
  rescue JSON::ParserError
    nil
  end
  rows.select { |h| h['detector'] == 'db_lock_auditor:read_modify_write' }
end

def reset_race_guard!(io)
  RaceGuard.reset_configuration!
  RaceGuard.context.reset!
  io.truncate(0)
  io.rewind
end

def configure_rmw!(io, wallet_class)
  RaceGuard.configure do |c|
    c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io))
    c.db_lock_read_modify_write_models(wallet_class)
    c.severity(:'db_lock_auditor:read_modify_write', :warn)
  end
end

def setup_ar!(db_path)
  ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: db_path)
  ActiveRecord::Schema.define do
    create_table :smoke_wallets, force: true do |t|
      t.integer :balance, null: false, default: 0
    end
  end
  Class.new(ActiveRecord::Base) do
    self.table_name = 'smoke_wallets'
  end
end

def expect_rmw_count!(io, expected, label)
  got = parse_rmw_lines(io).size
  return if got == expected

  smoke_fail!("#{label}: expected #{expected} RMW line(s), got #{got}. Buffer:\n#{io.string}")
end

def run_smoke
  db = File.join(Dir.tmpdir, "race_guard_smoke_#{Process.pid}.sqlite3")
  FileUtils.rm_f(db)

  ENV['RACK_ENV'] = 'development'
  io = StringIO.new
  wallet_class = setup_ar!(db)
  RaceGuard::ActiveRecord.install_transaction_tracking!
  RaceGuard::DBLockAuditor::ReadModifyWrite.install!

  reset_race_guard!(io)
  configure_rmw!(io, wallet_class)

  w = wallet_class.create!(balance: 10)
  x = w.balance
  w.update!(balance: x - 1)
  expect_rmw_count!(io, 1, 'RMW without lock')

  reset_race_guard!(io)
  configure_rmw!(io, wallet_class)
  w = wallet_class.create!(balance: 10)
  w.with_lock do
    b = w.balance
    w.update!(balance: b - 1)
  end
  expect_rmw_count!(io, 0, 'with_lock read+save')

  reset_race_guard!(io)
  configure_rmw!(io, wallet_class)
  w = wallet_class.create!(balance: 7)
  v = w.balance
  w.with_lock { w.update!(balance: v - 1) }
  expect_rmw_count!(io, 0, 'read outside with_lock')

  reset_race_guard!(io)
  configure_rmw!(io, wallet_class)
  w = wallet_class.create!(balance: 4)
  ActiveRecord::Base.transaction do
    w.lock!
    w.update!(balance: w.balance - 1)
  end
  expect_rmw_count!(io, 0, 'lock! then save in transaction')

  reset_race_guard!(io)
  configure_rmw!(io, wallet_class)
  w = wallet_class.create!(balance: 3)
  w.with_lock do
    w.with_lock do
      b = w.balance
      w.update!(balance: b - 1)
    end
  end
  expect_rmw_count!(io, 0, 'nested with_lock')

  reset_race_guard!(io)
  configure_rmw!(io, wallet_class)
  w_id = wallet_class.create!(balance: 10).id
  t1 = Thread.new do
    ActiveRecord::Base.connection_pool.with_connection do
      r = wallet_class.find(w_id)
      r.with_lock { r.update!(balance: r.balance - 1) }
    end
  end
  t2 = Thread.new do
    ActiveRecord::Base.connection_pool.with_connection do
      r = wallet_class.find(w_id)
      r.with_lock { r.update!(balance: r.balance - 1) }
    end
  end
  [t1, t2].each(&:join)
  expect_rmw_count!(io, 0, 'two threads with_lock')
  final = wallet_class.find(w_id).balance
  smoke_fail!("concurrency: expected balance 8, got #{final}") unless final == 8

  puts "smoke_db_lock_rmw: OK (#{db})"
ensure
  if defined?(ActiveRecord::Base) && ActiveRecord::Base.connected?
    ActiveRecord::Base.connection_pool.disconnect!
  end
  FileUtils.rm_f(db) if db
end

run_smoke if $PROGRAM_NAME == __FILE__
