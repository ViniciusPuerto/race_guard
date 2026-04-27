# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'generators/race_guard/install/install_generator'

RSpec.describe RaceGuard::Generators::InstallGenerator do
  let(:dest) { Dir.mktmpdir('race_guard_install_gen') }

  after do
    FileUtils.rm_rf(dest)
  end

  it 'writes config/initializers/race_guard.rb with configure block' do
    described_class.start([], destination_root: dest)
    path = File.join(dest, 'config/initializers/race_guard.rb')
    expect(File).to exist(path)
    body = File.read(path)
    expect(body).to include('RaceGuard.configure')
    expect(body).to include('production is inactive')
  end
end
