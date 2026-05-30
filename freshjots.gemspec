# frozen_string_literal: true

require_relative "lib/freshjots/version"

Gem::Specification.new do |spec|
  spec.name        = "freshjots"
  spec.version     = Freshjots::VERSION
  spec.authors     = ["Goran Arsov"]
  spec.email       = ["arsphy@yahoo.com"]

  spec.summary     = "Tiny Ruby client for the Fresh Jots API"
  spec.description = "Append-only notebooks for cron jobs, deploy scripts, and bots. Wraps the plain-text REST API at freshjots.com/api/v1."
  spec.homepage    = "https://github.com/Goran-Arsov/freshjots-ruby"
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.0"

  spec.metadata["homepage_uri"]      = spec.homepage
  spec.metadata["source_code_uri"]   = spec.homepage
  spec.metadata["bug_tracker_uri"]   = "#{spec.homepage}/issues"
  spec.metadata["documentation_uri"] = "https://freshjots.com/docs"

  spec.files         = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]
end
