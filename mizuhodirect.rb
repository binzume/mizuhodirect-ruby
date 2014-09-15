# -*- encoding: utf-8 -*-
#
#  みずほダイレクトβ
#    http://www.binzume.net/
require "kconv"
require "rexml/document"
require "time"

require_relative "httpclient"

require 'digest/sha1'
require 'securerandom'
require 'openssl'
require 'base64'

class MizuhoDirect
  attr_accessor :account

  def initialize(account = nil)
    @account_status = {
      "zandaka" => nil,
      "recentlog" => nil,
    }
    @base_url = 'https://web3.ib.mizuhobank.co.jp'
    if account
      login(account)
    end
  end

  def get_input_value html, name
    if html=~/<input\s[^>]*?name="#{name}"[^>]*?value="([^"]*)"/i
      $1
    end
  end

  def parse_form html
      formdata = {
        "_FRAMEID" => get_input_value(html,'_FRAMEID'),
        "_TARGETID" => get_input_value(html,'_TARGETID'),
        "_LUID" => "",
        "_SUBINDEX" => "",
        "_TOKEN"=> get_input_value(html,'_TOKEN'),
        "_FORMID" => get_input_value(html,'_FORMID'),
        "POSTKEY"=> get_input_value(html,'POSTKEY')
      }
      formdata
  end

  ##
  # ログイン
  def login(account)
    @account = account
    ua = "Mozilla/5.0 (Windows; U; Windows NT 5.1;) MizuhoDirectBot/0.1"
    @client = HTTPClient.new(:agent_name => ua)

    url = @base_url + '/servlet/LOGBNK0000000B.do'
    res = @client.get(url)

    raise "Login failed: login page." unless res.body =~ /<form[^>]+?action="([^"]+)"/i

    haraidashi(res.body, @account["ID"])

    res = sendid(res, @base_url + $1)

    if res.body=~/<input\s[^>]*?name="txbTestWord"/i
      res = aikotoba(res)
    end

    if res.body=~/<input\s[^>]*?name="txbTestWord"/i
      res = aikotoba(res)
    end

    if res.body=~/<input\s[^>]*?name="PASSWD_LoginPwdInput"/i
      res = sendpasswd(res)
    else
      raise "Login failed"
    end


    #puts res
    #puts res.body
    #puts url
    @formdata = parse_form(res.body)

    @account_status = {}
    html = res.body.toutf8

    if html=~/<span\s+id="txtCrntBal"[^>]*>([\d,]+)/
      @account_status[:total_balance] = $1.gsub(/,/,'').to_i
      @account_status['zandaka'] = @account_status[:total_balance]
    end

    if html=~/<span\s+id="txtLoginInfoCustNm"[^>]*>([^<]+)/
      @account_status[:name] = $1
    end

    if html=~/<span\s+id="txtLastUsgTm"[^>]*>([^<]+)/
      @account_status[:last_login] = $1.gsub('&nbsp;',' ')
    end

    if html=~/href=["'](\/servlet\/MENSRV0100901B.do[^"']*)/
      @logout_path = $1
    end
    @account_status["recentlog"] = _parse_recent(html)

    @login_success = true
    return @login_success
  end

  def haraidashi login_html, id
    raise "haraidashi js not detected" unless login_html=~/=\[j,"([\w\.\-]+)","(\w+)","(\w+.js)"\]/
    url = "https://#{$1}/#{$2}/"
    js = $3
    res = @client.get(url + js)

    raise "param:dn not found" unless res.body=~/=\[s,"HsrR\.html"\]\.join\("\/"\),\w+="([0-9a-f]{2,20})"/i
    dn = $1
    raise "param:n,e not found" unless res.body=~/\{n:\s*new\s*BigInteger\("([0-9a-f]{100,})",16\),e:\s*new\s*BigInteger\("([0-9a-f]{2,20})",16\)}/i
    n = $1
    e = $2


    def mgf seed,len
      t = "";
      for counter in 0..(len / 20).ceil
        t += Digest::SHA1.digest(seed + [counter].pack("N"));
      end
      t.slice(0,len)
    end

    def str_xor sa, sb
      sa.unpack('C*').zip(sb.unpack('C*')).map{ |a,b| a ^ b }.pack('C*')
    end

    hlen = 20
    salt = ""
    hs = Digest::SHA1.digest(salt)

    ps = "\x00".force_encoding("ascii-8bit") * ((n.length/2).to_i - id.length - 2 * hlen - 2)

    db = hs + ps + "\x01".force_encoding("ascii-8bit") + id

    rr =  SecureRandom.random_bytes(hlen)

    q = str_xor(db, mgf(rr,db.length))
    v = str_xor(rr, mgf(q,hlen))

    #puts "db" + db.length.to_s
    #p db
    #p db[225]

    mm = "\x00".force_encoding("ascii-8bit") + v + q

    #puts "mm #{mm.length}"
    #p mm
    #p mm.unpack('H*')[0]

    encrypted =  mm.unpack('H*')[0].to_i(16).to_bn.mod_exp(e.hex, n.hex).to_i.to_s(16)
    ud = Base64.encode64([encrypted,"1","LOGBNK_00000B"].join("|")).gsub(/\s+/,'')

    #p encrypted
    #p url + "cV4?cid=3&ud=" + ud + "&ci=0&dn=" + dn

    @client.get(url + "cV4?cid=3&ud=" + ud + "&ci=0&dn=" + dn)
    #p @client.cookies['haraidashi.ib.mizuhobank.co.jp']
    @client.cookies['web3.ib.mizuhobank.co.jp'].merge!(@client.cookies['haraidashi.ib.mizuhobank.co.jp'])

  end

  def sendid(res, url)
    postdata = parse_form(res.body)
    postdata["pm_fp"] = "version%3D3%2E2%2E0%2E0%5F3%26pm%5Ffpua%3Dmozilla%2F5%2E0%20%28windows%20nt%206%2E1%3B%20wow64%29%20applewebkit%2F537%2E36%20%28khtml%2C%20like%20gecko%29%20chrome%2F39%2E0%2E2145%2E4%20safari%2F537%2E36%7C5%2E0%20%28Windows%20NT%206%2E1%3B%20WOW64%29%20AppleWebKit%2F537%2E36%20%28KHTML%2C%20like%20Gecko%29%20Chrome%2F39%2E0%2E2145%2E4%20Safari%2F537%2E36%7CWin32%26pm%5Ffpsc%3D24%7C1920%7C1080%7C1080%26pm%5Ffpsw%3D%7Cpdf%26pm%5Ffptz%3D9%26pm%5Ffpln%3Dlang%3Dja%7Csyslang%3D%7Cuserlang%3D%26pm%5Ffpjv%3D1%26pm%5Ffpco%3D1%26pm%5Ffpasw%3Dwidevinecdmadapter%7Cpepflashplayer%7Cinternal%2Dremoting%2Dviewer%7Cinternal%2Dnacl%2Dplugin%7Cpdf%7Cnppdf32%7Cnpgeplugin%7Cnppicasa3%7Cnpwlpg%7Cnpunity3d32%7Cnpgoogleupdate3%26pm%5Ffpan%3DNetscape%26pm%5Ffpacn%3DMozilla%26pm%5Ffpol%3Dtrue%26pm%5Ffposp%3D%26pm%5Ffpup%3D%26pm%5Ffpsaw%3D1751%26pm%5Ffpspd%3D24%26pm%5Ffpsbd%3D%26pm%5Ffpsdx%3D%26pm%5Ffpsdy%3D%26pm%5Ffpslx%3D%26pm%5Ffpsly%3D%26pm%5Ffpsfse%3D%26pm%5Ffpsui%3D%26pm%5Fos%3DWindows%26pm%5Fbrmjv%3D39%26pm%5Fbr%3DChrome%26pm%5Finpt%3D%26pm%5Fexpt%3D"
    postdata["txbCustNo"] = @account["ID"]

    res = @client.post(url , postdata)
    #puts url
    #p postdata, res, res.header['location']
    #puts res.body

    raise "Login failed: account id." unless res.status==302
    url = res.header['location'].first
    @client.get(url)
  end

  def aikotoba(res)
      raise "aikotoba fail" unless res.body=~/<span id="txtQuery">([^<]+)/
      q = $1.toutf8
      puts "AIKOTOBA? " + q
      if res.body =~ /<form[^>]+?action="([^"]+)"/i
        url = @base_url + $1
      else
        url = @base_url + "/servlet/LOGWRD0010001B.do"
      end

      ans = account["QA"].find {|qa| q.index(qa["q"]) }

      raise "aikotoba no_answer" unless ans
      p ans

      postdata = parse_form(res.body)
      postdata["chkConfItemChk"] = "on"
      postdata["txbTestWord"] = ans['a'].tosjis

      res = @client.post(url , postdata)
      #p url
      #p postdata
      #p res
      #puts res.body
      raise "Login failed: aikotoba." unless res.status==302

      @client.get(res.header['location'][0])
  end


  def sendpasswd(res)
      if res.body =~ /<form[^>]+?action="([^"]+)"/i
        url = @base_url + $1
      else
        url = @base_url + "/servlet/LOGBNK0000501B.do"
      end

      postdata = parse_form(res.body)
      postdata["PASSWD_LoginPwdInput"] = @account["PASS"]

      res = @client.post(url , postdata)
      #p url
      #p postdata
      #p res
      #puts res.body
      raise "Login failed: passwd." unless res.status==302

      @client.get(res.header['location'][0])
  end

  ##
  # ログアウト
  def logout
    unless @login_success
      return
    end
    return @client.get(@base_url + @logout_path) if @logout_path
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
    @account_status[:total_balance]
  end

  ##
  # 直近の取引履歴
  # とってきた結果はインスタンスに保持する
  def recent
    unless @account_status && @account_status["recentlog"]
      res = @client.post(@base_url + "/servlet/MENSRV0100003B.do", @formdata)
      res = @client.get(res.header['location'].first) if res.status==302
      @account_status["recentlog"] = _parse_recent(res.body.toutf8)
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
    html.scan(/<span\s+id="txtDate_.*?<\/tr>/mi) { |m|
      date = if m=~/<span\s+id="txtDate_\d+">([^<]*)</
        $1.gsub('.','-')
      end
      desc = if m=~/<span\s+id="txtTransCntnt_\d+">([^<]*)</
        $1.gsub('&nbsp;',' ')
      end
      a = if m=~/<span\s+id="txtDrawAmnt_\d+">([\d,]+)/
        $1.gsub(',','').to_i
      end
      b = if m=~/<span\s+id="txtDpstAmnt_\d+">([\d,]+)/
        $1.gsub(',','').to_i
      end
      recent << [date, a, b,desc]
    }
    recent
  end

  #  from 3 months ago... to today
  def get_history from,to
    fdate = Time.parse(from)
    tdate = Time.parse(to)

    res = @client.post(@base_url + "/servlet/MENSRV0100003B.do", @formdata)
    res = @client.get(res.header['location'].first) if res.status==302

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

