# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'mongo/lock/version'

Gem::Specification.new do |gem|
  gem.name          = "mongo-lock"
  gem.version       = Mongo::Lock::VERSION
  gem.authors       = ["Jay Feldblum"]
  gem.email         = ["yfeldblum@gmail.com"]
  gem.description   = %q{Mongo::Lock}
  gem.summary       = %q{Mongo::Lock}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
end
