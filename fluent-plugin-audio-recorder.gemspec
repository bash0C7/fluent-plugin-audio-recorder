lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name    = "fluent-plugin-audio-recorder"
  spec.version = "0.1.0"
  spec.authors = ["bash0C7"]
  spec.email   = ["ksb.4038.nullpointer+github@gmail.com"]

  spec.summary       = %q{Fluentd input plugin for recording audio from macOS devices}
  spec.description   = %q{A Fluentd input plugin that records audio from macOS devices with silence detection}
  spec.homepage      = "https://github.com/bash0C7/fluent-plugin-audio-recorder"
  spec.license       = "Apache-2.0"

  spec.files         = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 2.6.2"
  spec.add_development_dependency "rake", "~> 13.2.1"
  spec.add_development_dependency "test-unit", "~> 3.6.7"
  spec.add_runtime_dependency "fluentd", [">= 0.14.10", "< 2"]
  spec.add_runtime_dependency "streamio-ffmpeg", "~> 3.0"
  spec.add_runtime_dependency "fileutils", "~> 1.6"
end
