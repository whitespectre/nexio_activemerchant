# frozen_string_literal: true

require_relative 'lib/nexio_activemerchant/version'

Gem::Specification.new do |spec|
  spec.name          = 'nexio_activemerchant'
  spec.version       = NexioActivemerchant::VERSION
  spec.authors       = %w[Whitespectre]
  spec.email         = %w[hello@whitespectre.com]

  spec.summary       = 'ActiveMechant gateway for Nexio'
  spec.homepage      = 'https://github.com/whitespectre/nexio_activemerchant'
  spec.required_ruby_version = Gem::Requirement.new('>= 2.3.0')

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/whitespectre/nexio_activemerchant'
  spec.metadata['changelog_uri'] = 'https://github.com/whitespectre/nexio_activemerchant/blob/master/CHANGELOG'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'activemerchant'
  spec.add_dependency 'json'
end
