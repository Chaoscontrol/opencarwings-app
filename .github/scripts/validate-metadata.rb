#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

config_path = "opencarwings/config.yaml"
translation_path = "opencarwings/translations/en.yaml"

config = YAML.safe_load_file(config_path, permitted_classes: [], permitted_symbols: [], aliases: false)
translations = YAML.safe_load_file(translation_path, permitted_classes: [], permitted_symbols: [], aliases: false)

abort "config.yaml must be a mapping" unless config.is_a?(Hash)
abort "translation YAML must be a mapping" unless translations.is_a?(Hash)

required = %w[name version slug arch ports options schema]
missing = required.reject { |key| config.key?(key) }
abort "config.yaml missing keys: #{missing.join(', ')}" unless missing.empty?

version = config.fetch("version").to_s
abort "invalid app version: #{version}" unless version.match?(/\A\d+\.\d+\.\d+(?:-\d+)?\z/)
abort "unexpected production slug" unless config.fetch("slug") == "opencarwings"
abort "amd64 architecture missing" unless Array(config.fetch("arch")).include?("amd64")

expected_ports = ["8124/tcp", "8125/tcp", "55230/tcp"]
missing_ports = expected_ports.reject { |port| config.fetch("ports").key?(port) }
abort "config.yaml missing ports: #{missing_ports.join(', ')}" unless missing_ports.empty?

puts "metadata-ok"
