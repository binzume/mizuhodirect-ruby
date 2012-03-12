#!/usr/bin/ruby -Ku
require "rubygems"
require 'yaml'
require_relative "mizuhodirect"

mizuho_account = YAML.load_file('mizuho_account.yaml')

# login
m = MizuhoDirect.new
unless m.login(mizuho_account)
  puts "LOGIN ERROR"
end

begin
  account_status = m.get_top

  puts 'total: ' + account_status["zandaka"].to_s
  account_status["recentlog"].each do |row|
    p row
  end

ensure
  # logout
  m.logout
end

puts "ok"

