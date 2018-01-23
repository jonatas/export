lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'export/version'

Gem::Specification.new do |spec|
  spec.name          = 'export'
  spec.version       = Export::VERSION
  spec.authors       = ['Jônatas Davi Paganini']
  spec.email         = ['jonatasdp@gmail.com']

  spec.summary       = 'Allow you export your data with options'
  spec.description   = 'Export a dump with options'
  spec.homepage      = 'http://ideia.me'
  spec.license       = 'MIT'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features|examples)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.13'
  spec.add_development_dependency 'pg', '~> 0.20'
  spec.add_development_dependency 'pry-byebug', '~> 3.4.1'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rspec-its', '~> 1.2.0'
  spec.add_development_dependency 'rubocop', '~> 0.52.1'
  spec.add_development_dependency 'rubocop-rspec', '~> 1.20.0'
  spec.add_development_dependency 'simplecov', '~> 0.15.1'
  spec.add_dependency 'activerecord', '~> 5.0'
  spec.add_dependency 'activesupport', '~> 5.0'
  spec.add_dependency 'ffaker', '~> 2.4.0'
  spec.add_dependency 'rake', '~> 10.0'
end
