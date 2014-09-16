#!/usr/bin/ruby -Ku
# -*- encoding: utf-8 -*-

require 'yaml'
require_relative 'mizuhodirect'

mizuho_account = YAML.load_file('mizuho_account.yaml')
bank = MizuhoDirect.new

# login
unless bank.login(mizuho_account)
  puts 'LOGIN ERROR'
  exit
end

begin
  puts 'total: ' + bank.total_balance.to_s
  bank.recent.each do |row|
    p row
  end

  #p bank.get_history('2014-08-01','2014-09-16')

  #if bank.total_balance > 5000000
  #  # 振込み (登録住み口座のニックネーム:string,金額:int,第２暗証番号:string)
  #  if bank.transfer_to_registered_account('テスト', 3000000, "1234567890")
  #    puts "transfer ok"
  #  end
  #end

rescue => e
  p e
ensure
  # logout
  bank.logout
end

puts "ok"

