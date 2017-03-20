$LOAD_PATH << "#{File.expand_path(__dir__)}/../../../../lib"
require 'export'
require 'benchmark'
require 'json'

namespace :export do
  def strip_email(email)
    username = email.split('@').first
    "#{username}@example.com"
  end

  def explore(table)
    columns = table.singularize.camelize.safe_constantize.column_names
    buffer = []
    columns.each do |column|
      case column
      when /email/
        buffer << suggest_email(column)
      when /password/
        buffer << suggest_unique_password(column)
      when /name/
        buffer << suggest_ffaker_names(column)
      end
    end
    buffer.join("\n  ") if buffer.any?
  end

  def suggest_email(column)
    'replace %s, -> (r) { "#{r.email.split(\'@\').first}@example.com" }' % column.to_sym.inspect
  end

  def suggest_unique_password(column)
    'replace %s, \'password\'' % column.to_sym.inspect
  end

  def suggest_ffaker_names(column)
    'replace %s, -> { FFaker::Name.name }' % column.to_sym.inspect
  end

  task init: :environment do
    ignored = %w[schema_migrations ar_internal_metadata]
    tables = ActiveRecord::Base.connection.tables
    (tables - ignored).each do |table|
      extra_data = explore(table)
      if extra_data
        puts <<-RUBY
Export.table '#{table}' do
  #{extra_data}
end

        RUBY
      else
        puts <<-RUBY
Export.table '#{table}'
        RUBY
      end
    end

  end
  desc "Export a dump with transformed data"
  task dump: :environment do

    table = Export.table 'users' do
      replace :password, 'password'
      replace :email, -> (record) { strip_email(record.email) }
      replace :full_name, -> (record) { record.full_name.reverse }
    end
    dump = Export::Dump.new(table)
    Benchmark.bm do |bm|
      bm.report("fetch records") { @users = User.all.to_a }
      bm.report("dump process") { @result = dump.process(@users) }
      bm.report("to_json") { @json = @result.to_json }
      bm.report("write json file") { File.open('results.json', 'w+') {|f|f.puts @json } }
    end
    require 'pry'
    binding.pry


  end
end

