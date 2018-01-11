require 'simplecov'
SimpleCov.start do
  add_filter 'support/statement_matcher.rb'
end

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'pry'
require 'export'
require 'rspec/its'
require 'active_record'
require 'yaml'
require 'ffaker'
require 'support/database_setup'
require 'support/statement_matcher'

connection_info = YAML.load_file('config/database.yml')['test']
ActiveRecord::Base.establish_connection(connection_info)

RSpec.configure do |config|
  config.around do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
