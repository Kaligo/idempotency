# frozen_string_literal: true

require_relative 'lib/idempotency/version'

Gem::Specification.new do |spec|
  spec.name        = 'idempotency'
  spec.version     = Idempotency::VERSION
  spec.authors     = ['Vu Hoang']
  spec.email       = 'vu.hoang@ascenda.com'

  spec.summary       = 'Caching requests for idempotency purpose'
  spec.description   = 'Caching requests for idempotency purpose'
  spec.homepage      = 'https://www.ascenda.com'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.1.0'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = 'https://rubygems.pkg.github.com/kaligo'

    spec.metadata['homepage_uri'] = spec.homepage
    spec.metadata['source_code_uri'] = 'https://www.ascenda.com'
  else
    raise 'RubyGems 2.0 or newer is required to protect against ' \
          'public gem pushes.'
  end

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end

  spec.require_paths = ['lib']
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.add_dependency 'dry-configurable'
  spec.add_dependency 'msgpack'
  spec.add_dependency 'redis'
end
