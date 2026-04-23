# frozen_string_literal: true

require 'json'
require 'socket'
require 'stringio'

require 'race_guard'
require 'race_guard/interceptors'

RSpec.describe RaceGuard::Interceptors do
  include EnvSpecHelpers

  after do
    RaceGuard.reset_configuration!
    RaceGuard.context.reset!
    described_class.reset_install_registry_for_tests!
  end

  describe 'Net::HTTP' do
    it 'emits commit_safety:net_http on request' do
      with_isolated_env(rack: 'development') do
        io = StringIO.new
        RaceGuard.configure { |c| c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io)) }
        described_class.install_net_http!

        server = TCPServer.new('127.0.0.1', 0)
        port = server.addr[1]
        t = Thread.new do
          s = server.accept
          s.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK")
          s.close
        end

        begin
          Net::HTTP.start('127.0.0.1', port) do |http|
            http.request(Net::HTTP::Get.new('/'))
          end
        ensure
          t.join(2)
          server.close
        end

        line = io.string.lines.last
        expect(line.to_s.strip).not_to be_empty
        payload = JSON.parse(line)
        expect(payload['detector']).to eq('commit_safety:net_http')
        expect(payload['context']['http_method']).to eq('GET')
      end
    end
  end

  describe 'Faraday' do
    it 'emits commit_safety:faraday on run_request' do
      with_isolated_env(rack: 'development') do
        require 'faraday'
        io = StringIO.new
        RaceGuard.configure { |c| c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io)) }
        described_class.install_faraday!

        stubs = Faraday::Adapter::Test::Stubs.new do |stub|
          stub.get('/ping') { [200, { 'Content-Type' => 'text/plain' }, 'pong'] }
        end
        conn = Faraday.new do |b|
          b.adapter :test, stubs
        end
        conn.get('/ping')

        line = io.string.lines.last
        expect(line.to_s.strip).not_to be_empty
        payload = JSON.parse(line)
        expect(payload['detector']).to eq('commit_safety:faraday')
        expect(payload['context']['url']).to include('/ping')
      end
    end
  end

  describe 'ActiveJob' do
    it 'emits commit_safety:active_job on perform_later' do
      with_isolated_env(rack: 'development') do
        require 'active_job'
        io = StringIO.new
        RaceGuard.configure { |c| c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io)) }
        described_class.install_active_job!

        ActiveJob::Base.queue_adapter = :test
        stub_const('InterceptorsSpecJob', Class.new(ActiveJob::Base) do
          def perform(value)
            value
          end
        end)

        InterceptorsSpecJob.perform_later(42)

        line = io.string.lines.last
        expect(line.to_s.strip).not_to be_empty
        payload = JSON.parse(line)
        expect(payload['detector']).to eq('commit_safety:active_job')
        expect(payload['context']['job_class']).to include('InterceptorsSpecJob')
      end
    end
  end

  describe 'ActionMailer' do
    it 'emits commit_safety:action_mailer on deliver_later' do
      with_isolated_env(rack: 'development') do
        require 'active_job'
        require 'action_mailer'

        io = StringIO.new
        RaceGuard.configure { |c| c.add_reporter(RaceGuard::Reporters::JsonReporter.new(io)) }
        described_class.install_action_mailer!

        ActiveJob::Base.queue_adapter = :test
        ActionMailer::Base.delivery_method = :test

        stub_const('InterceptorsSpecMailer', Class.new(ActionMailer::Base) do
          default from: 'from@example.com'

          def hello
            mail(to: 'to@example.com', subject: 'Hi', body: 'Body')
          end
        end)

        InterceptorsSpecMailer.hello.deliver_later

        line = io.string.lines.last
        expect(line.to_s.strip).not_to be_empty
        payload = JSON.parse(line)
        expect(payload['detector']).to eq('commit_safety:action_mailer')
        expect(payload['message']).to include('deliver_later')
        expect(payload['context']).to have_key('in_transaction')
      end
    end
  end

  describe 'Emitter resilience' do
    it 'does not raise when RaceGuard.report raises' do
      allow(RaceGuard).to receive(:report).and_raise(StandardError, 'boom')
      expect do
        RaceGuard::Interceptors::Emitter.emit(:test_emit, 'hello', 'k' => 'v')
      end.not_to raise_error
    end
  end

  describe '#install_all!' do
    it 'installs every available interceptor without raising' do
      require 'active_job'
      require 'action_mailer'
      require 'faraday'

      expect { described_class.install_all! }.not_to raise_error
    end
  end
end
