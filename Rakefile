#!/usr/bin/env rake
require "bundler/gem_tasks"

require 'rake/clean'
require 'rake/testtask'

task :default => :spec

task :spec do
  sh "rspec spec"
end

desc "Build the gem, create a git tag, and push to git. If the build passes, CircleCI will publish to packagecloud"
task :release, [:remote] => %w(build release:guard_clean release:source_control_push)
