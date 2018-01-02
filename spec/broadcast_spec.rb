require 'spec_helper'

describe Export::Broadcast do
  context 'when ping pong toy' do
    subject do
      described_class.new do
        on('ping') { puts 'ping'; publish 'pong' }
        on('pong') { puts 'pong' }
      end
    end

    context 'when resume work' do
      it 'outputs ping pong stuff' do
        expect do
          subject.publish 'ping'
          sleep 0.1
        end.to output("ping\npong\n").to_stdout
      end

      it 'fails trying to publish in non defined channels' do
        expect do
          subject.publish 'pung'
        end.to raise_error Export::Broadcast::InvalidChannel,
                           'Unrecognized pung. Currently allowed: ping, pong.'
      end
    end
  end

  context 'when pipeline' do
    subject do
      described_class.new do
        on('fetch') { |d|  puts "fetch: #{d}"; publish('filter', d.map { |e| e + 1 }) }
        on('filter') { |d| puts "map: #{d}"; publish('store', d.select(&:even?)) }
        on('store') { |d| puts  "filter: #{d}" }
      end
    end

    specify do
      expect do
        subject.publish 'fetch', [1, 2, 3, 4, 5, 6]
        sleep 0.1 # as it's consumed by threads, let's wait a bit 8-)
      end.to output(<<~OUTPUT).to_stdout
        fetch: [1, 2, 3, 4, 5, 6]
        map: [2, 3, 4, 5, 6, 7]
        filter: [2, 4, 6]
      OUTPUT
    end
  end
end
