This is a MizohoDirect (Mizuho internet banking) library for Ruby.

- http://www.mizuhobank.co.jp/direct/index.html

Require:

httpclientとhpricotが必要です．gemからインストールしてください．→不要になりました

Exapmple:

# mizuho_account.yaml
ID: "1234567890"
PASS: "********"
QA:
  - q: "中学校"
    a: "山田太郎"
  - q: "研究室"
    a: "hoge"
  - q: "都市"
    a: "fuga"

みずほダイレクトのアカウント情報と，秘密の質問を識別するための部分文字列＋質問への回答を設定してください．

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
rescue => e
  p e
ensure
  # logout
  bank.logout
end

puts "ok"



