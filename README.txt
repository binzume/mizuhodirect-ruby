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

# mizuhodirect_sample.rb

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



