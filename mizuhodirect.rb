# -*- encoding: utf-8 -*-
#
#  みずほダイレクトβ
#    http://www.binzume.net/
require "kconv"
require "rexml/document"
require "time"
#require "hpricot"
require_relative "httpclient"

class MizuhoDirect
  attr_accessor :account

  def initialize(account = nil)
    @account_status = {
      "zandaka" => nil,
      "recentlog" => nil,
    }
    if account
      login(account)
    end
  end

  ##
  # ログイン
  def login(account)
    @account = account
    ua = "Mozilla/5.0 (Windows; U; Windows NT 5.1;) MizuhoDirectBot/0.1"
    @client = HTTPClient.new(:agent_name => ua)

    url = 'https://web.ib.mizuhobank.co.jp/servlet/mib?xtr=Emf00000'
    res = @client.get(url)
    if res.status==302
      url = res.header['location'].first
      url.gsub!(/\"/,"")
    else
      if res.body =~ /<form[^>]+?action="([^"]+)"/i
        url = $1
        res = @client.get(url) # dummy (avoid bug for httpclient.rb )
      end
    end

    res = sendid(url)

    if res.status==302 && res.header['location'].first =~ /Emf00100/
      url = res.header['location'].first
      url.gsub!(/\"/,"")
      res = aikotoba(url)
    end

    if res.status==302 && res.header['location'].first =~ /Emf00100/
      url = res.header['location'].first
      url.gsub!(/\"/,"")
      res = aikotoba(url)
    end

    if res.status==302 && res.header['location'].first =~ /Emf00005/
      url = res.header['location'].first
      url.gsub!(/\"/,"")
      res = sendpasswd(url)
    end

    if res.status==302 && res.header['location'].first =~ /Emf02000/
      @login_success = true
      if res.header['location'].first =~ /https:\/\/([^\/]+)\//
        @host = $1
      end
    else
      @login_success = nil
    end
    return @login_success
  end

  def sendid(url)
    postdata={
      "pm_fp"=>"",
      "KeiyakuNo"=>@account["ID"],
      "Next"=>"next"
    }
    return  @client.post(url , postdata)
  end

  def aikotoba(url)
    postdata = {
      "NLS"=>"JP",
      "Token"=>"",
      "jsAware"=>"on",
      "frmScrnID"=>"Emf00000",
      "rskAns"=>"",
      "Next"=>"next"
    }
    body = @client.get_content(url).toutf8
    account["QA"].each do |qa|
      if body.index(qa["q"])
        puts "Q:" + qa["q"]
        puts "A:" + qa["a"]
        postdata["rskAns"] = qa["a"].tosjis
      end
    end

    return @client.post(url , postdata)
  end

  def sendpasswd(url)
    postdata = {
      "NLS"=>"JP",
      "jsAware"=>"on",
      "pmimg"=>"",
      "frmScrnID"=>"Emf00000",
      "Anshu1No"=> @account["PASS"],
      "login"=>"login"
    }
    return @client.post(url , postdata)
  end

  ##
  # ログアウト
  def logout
    unless @login_success
      return
    end
    return @client.get('https://'+@host+'/servlet/mib?xtr=EmfLogOff');
  end

  def account_status
    unless @account_status && @account_status["recentlog"]
      get_top
    end
    @account_status
  end

  ##
  # 残高確認
  # とってきた結果はインスタンスに保持する
  def total_balance
    unless @account_status && @account_status["recentlog"]
      get_top
    end
    @account_status['zandaka']
  end

  ##
  # 直近の取引履歴
  # とってきた結果はインスタンスに保持する
  def recent
    unless @account_status && @account_status["recentlog"]
      get_top
    end
    @account_status["recentlog"]
  end


  def get_top
    unless @login_success
      return
    end
    res = @client.get("https://#{@host}/servlet/mib?xtr=Emf02000")
    html = res.body.toutf8
    unless html
      return
    end
    account_status = {
      "zandaka" => nil,
      "recentlog" => [],
    }

    if html =~ /&nbsp;現在残高<\/DIV>.*?>([\d,]+)\s+円&nbsp;<\/DIV>/m
      zandaka = $1;
      account_status["zandaka"] = zandaka.gsub(/,/,"").to_i
    end

    account_status["recentlog"] = _parse_recent(html)

    @account_status = account_status
    return account_status
  end

  def _parse_recent html
    recent = []

    # use rexml
    html.scan(/<table[^>]*>.*?<\/table>/mi) {|tbl|
      tbl.gsub!(/^.+(<table[^\w])/im,'\1')
      unless tbl.index('お取引内容')
        next
      end
      tbl.gsub!(/<\/?DIV[^>]*>/,'')
      tbl.gsub!(/<(\w+)[^>]*>/,'<\1>')
      doc = REXML::Document.new(tbl)

      trs = []
      doc.each_element('TABLE/TR') {|tr|
        trs << tr
      }
      trs.shift
      trs.each {|tr|
        tds = []
        tr.each_element('TD') {|td|
          tds << td.text.gsub('&nbsp;',' ')
        }
        expend = tds[1].gsub(/,/,'').to_i
        deposit = tds[2].gsub(/,/,'').to_i
        recent << [tds[0].gsub('.','-'), expend, deposit, tds[3]]
      }

    }
    return recent

    # use hpricot
    doc = Hpricot(html);
    trs = (doc / 'table[text()*="お取引内容"]').last  / 'tr';
    trs.shift
    trs.each do |tr|
      tds = (tr / 'td' )
      expend = tds[1].to_plain_text.gsub(/,/,'').to_i
      deposit = tds[2].to_plain_text.gsub(/,/,'').to_i
      recent.push [tds[0].to_plain_text, expend, deposit, tds[3].to_plain_text]
    end

  end

  #  from 3 months ago... to today
  def get_history from,to
    fdate = Time.parse(from)
    tdate = Time.parse(to)
    postkey = nil

    res = @client.get("https://#{@host}/servlet/mib?xtr=Emf04000")

    if res.body =~/<INPUT TYPE=HIDDEN NAME="EMFPOSTKEY" VALUE="(\w+)"/
      postkey = $1
    end

    postdata={
      "Token"=>"",
      "NLS"=>"JP",
      "REDISP"=>"OFF",
      "EMFPOSTKEY"=>postkey,
      "hidColor"=>"00",
      "menuposition"=>"0",
      "pm_fp"=>"",
      "SelAcct"=>"0",  # account
      "REDISP"=>"OFF",
      "INQUIRY_MONTH_TYPE"=>"THIS_MONTH",
      "INQUIRY_TYPE"=>"RANGE",
      "SFYear"=> fdate.year,
      "SFMonth"=> fdate.month,
      "SFDay"=> fdate.mday,
      "STYear"=> tdate.year,
      "STMonth"=> tdate.month,
      "STDay"=> tdate.mday,
      "Inquiry"=>"",
    }

    res = @client.post("https://#{@host}/servlet/mib?xtr=Emf04000", postdata)
    if res.status==302
      res = @client.get(res.header['location'].first)
    end
    html = res.body.toutf8
    # puts html
    return _parse_recent(html)
  end

  ##
  # move to registered account
  # 振込み (登録住み口座のニックネーム:string,金額:int,第２暗証番号:string)
  # email,message(全角文字のみ)を指定するとメールで通知.
  def transfer_to_registered_account nick, amount, pass2, email = nil, message = nil
    postkey = nil

    res = @client.get("https://#{@host}/servlet/mib?xtr=Emf01000&mbid=MB_R011N050")
    if res.status==302
      res = @client.get(res.header['location'].first)
      if res.body =~/<INPUT TYPE=HIDDEN NAME="EMFPOSTKEY" VALUE="(\w+)"/
        postkey = $1
      end
    else
      puts res.body
      return
    end

    if res.body.toutf8 =~ /<INPUT TYPE="radio" NAME="InknKzRadio" VALUE="(\d+)" ><\/DIV><\/TD>\s+<TD[^>]*><DIV[^>]*>&nbsp;#{nick}<\/DIV>/
      n = $1
    else
      puts res.body
      return
    end

    postdata={
      "Token"=>"",
      "NLS"=>"JP",
      "REDISP"=>"OFF",
      "EMFPOSTKEY"=>postkey,
      "hidColor"=>"00",
      "menuposition"=>"0",
      "pm_fp"=>"",

      "UktkNo"=>"",
      "OutknKzBox"=>"0",
      "OutknCustNmUmu"=>"no",
      "OutknCustNm"=>"",
      "InknKzRadio"=>n,
      "Next"=>"",
    }
    res = @client.post("https://#{@host}/servlet/mib?xtr=Emf05000", postdata)
    if res.status==302
      res = @client.get(res.header['location'].first)
      #puts res.body
      if res.body =~/<INPUT TYPE=HIDDEN NAME="EMFPOSTKEY" VALUE="(\w+)"/
        postkey = $1
      end
    end

    postdata={
      "Token"=>"",
      "NLS"=>"JP",
      "REDISP"=>"OFF",
      "EMFPOSTKEY"=>postkey,
      "hidColor"=>"00",
      "menuposition"=>"0",
      "pm_fp"=>"",

      "InputThrKn"=>amount,
      "PayeeEmail"=>email,
      "PayeeEmailMessage"=>message &&message.tosjis,
      "Next"=>"",
    }
    res = @client.post("https://#{@host}/servlet/mib?xtr=Emf05070", postdata)
    if res.status==302
      res = @client.get(res.header['location'].first)
      #puts res.body
      if res.body =~/<INPUT TYPE=HIDDEN NAME="EMFPOSTKEY" VALUE="(\w+)"/
        postkey = $1
      end
    else
      p postdata
      puts res.body
      return
    end

    pass2pos = []
    if res.body.toutf8 =~/第2暗証番号の左から<FONT COLOR="#F00000">(\d)番目<\/FONT>、<FONT COLOR="#F00000">(\d)番目<\/FONT>、<FONT COLOR="#F00000">(\d)番目<\/FONT>、<FONT COLOR="#F00000">(\d)番目<\/FONT>/
      pass2pos = [$1.to_i,$2.to_i,$3.to_i,$4.to_i]
    else
      return
    end
    postdata={
      "Token"=>"",
      "NLS"=>"JP",
      "REDISP"=>"OFF",
      "EMFPOSTKEY"=>postkey,
      "hidColor"=>"00",
      "menuposition"=>"0",
      "pm_fp"=>"",

      "CheckAnshu2"=>"on",
      "Anshu2"=>pass2[pass2pos[0]-1],
      "Anshu2_2"=>pass2[pass2pos[1]-1],
      "Anshu2_3"=>pass2[pass2pos[2]-1],
      "Anshu2_4"=>pass2[pass2pos[3]-1],
      "ButtonExecHurikomi"=>"",
    }
    res = @client.post("https://#{@host}/servlet/mib?xtr=Emf05080", postdata)
    if res.status==302
      res = @client.get(res.header['location'].first)
      puts res.body
    else
      p postdata
      puts res.body
      return
    end

    return true
  end

  def zandaka
    @account_status['zandaka']
  end

end

