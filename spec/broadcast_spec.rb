require 'spec_helper'

describe Export::Broadcast do
  context 'ping pong toy' do
    subject do
      described_class.new do
        on('ping') { puts 'ping' ; publish 'pong' }
        on('pong') { puts 'pong' }
      end
    end

    context '.resume_work' do
      it 'outputs ping pong stuff' do
        expect do
          subject.publish 'ping'
          subject.resume_work
        end.to output("ping\npong\n").to_stdout
      end

      it 'fails trying to publish in non defined channels' do
        expect do
          subject.publish 'pung'
          subject.resume_work
        end.to raise_error Export::Broadcast::InvalidChannel,
          "Unrecognized pung. Currently allowed: ping, pong"
      end
    end
  end

  context 'pipeline' do
    subject do
      described_class.new do
        on('fetch') {|d| publish('filter',*d.map{|e|e + 1}) }
        on('filter') {|d| publish('store', *d.select{|e|e % 2 == 0}) }
        on('store') {|d| print "#{d}"}
      end
    end

    context '.resume_work' do
      it 'outputs ping pong stuff' do
        expect do
          subject.publish 'fetch', *[1,2,3,4,5,6]
          subject.resume_work
        end.to output("[2, 4, 6]").to_stdout
      end
    end
  end
end
