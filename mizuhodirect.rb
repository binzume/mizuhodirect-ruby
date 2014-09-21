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
      :total_balance => nil,
      :name => nil,
      "recentlog" => nil,
    }
    @base_url = 'https://web1.ib.mizuhobank.co.jp/servlet/'
    @formdata = {}
    @login_success = false
    ua = "Mozilla/5.0 (Windows; U; Windows NT 5.1;) MizuhoDirectBot/0.1"
    @client = HTTPClient.new(:agent_name => ua)
    if account
      login(account)
    end
  end

  ##
  # ログイン
  def login(account)
    @account = account

    res = @client.get(@base_url + 'LOGBNK0000000B.do')
    @base_url = $1 if res.body =~/<base href="(https?:[^"]+\/servlet\/)">/

    raise "Login failed: login page." unless res.body =~ /<form[^>]+?action="([^"]+)"/i
    path = $1

    haraidashi(res.body, @account["ID"])

    res = sendid(res, path)
    res = aikotoba(res) if  res.body=~/<input\s[^>]*?name="txbTestWord"/i
    res = aikotoba(res) if  res.body=~/<input\s[^>]*?name="txbTestWord"/i

    raise "Login failed" unless res.body=~/<input\s[^>]*?name="PASSWD_LoginPwdInput"/i

    res = sendpasswd(res)
    @account_status = _parse_top(res.body.toutf8)

    @login_success = true
    true
  end

  ##
  # ログアウト
  def logout
    unless @login_success
      return
    end
    return @client.get(base_url_root + @logout_path) if @logout_path
  end

  def account_status
    unless @account_status && @account_status["recentlog"]
      get_top
    end
    @account_status
  end

  ##
  # 残高確認
  def total_balance
    @account_status[:total_balance]
  end

  ##
  # 直近の取引履歴
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

    res = execute('MENSRV0100001B')
    @account_status = _parse_top(res.body.toutf8)

    return account_status
  end

  # ex. get_history('2014-08-01','2014-09-16')
  #  from 3 months ago... to today
  def get_history from, to, acc = 0
    fdate = Time.parse(from)
    tdate = Time.parse(to)
    mode = 2

    execute('MENSRV0100003B')

    res = execute('ACCHST0400001B', {
      "lstAccSel" => acc,
      "rdoInqMtdSpec" => mode,
      "lstTargetMnthSel" => "NO_WRITE", # (THIS_MONTH,PREV_MONTH,BEFORE_LASTMONTH,NO_WRITE)
      "lstDateFrmYear"=> fdate.year,
      "lstDateFrmMnth"=> fdate.month,
      "lstDateFrmDay"=> fdate.mday,
      "lstDateToYear"=> tdate.year,
      "lstDateToMnth"=> tdate.month,
      "lstDateToDay"=> tdate.mday
    })

    return _parse_history(res.body.toutf8)
  end

  ##
  # move to registered account
  # 振込み (登録住み口座のニックネーム:string,金額:int,第２暗証番号:string)
  # email,message(全角文字のみ)を指定するとメールで通知.
  def transfer_to_registered_account nick, amount, pass2, email = nil, message = nil, acc = 0

    res = execute('MENSRV0100004B')

    registerd = {}
    res.body.toutf8.scan(/<span\s+id="txtNickNm_(\d+)">([^<]+)</mi) {|m|
      registerd[$2] = $1.to_i
    }
    p registerd

    raise "not registerd: #{nick}" unless registerd[nick]

    res = execute('TRNTRN0500001B', {
      "lstAccLst" => acc,
      "rdoChgOrNot" => "no", # use name?
      "txbClntNmConfigClntNm" => "", # name
      "rdoTrnsfreeSel"=> registerd[nick]
    })

    res = execute('TRNTRN0507001B', {
      "txbTrnfrAmnt" => amount,
      "txbRecpMailAddr" => email,
      "txaTxt" => message
    })

    if res.body.toutf8 =~/<div\s[^>]*id="ErrorMessage"[^>]*>(.+?)<\//
      puts $1
      raise "ERR: #{$1}"
    end

    pp = []
    res.body.toutf8.scan(/<span id="txtScndPwdDgt(\d+)">(\d+)</) {|m|
      pp[$1.to_i] = $2.to_i
    }
    raise "error pass2 get digits." unless pp[1] && pp[2] && pp[3] && pp[4]

    postdata = {
      "PASSWD_ScndPwd1" => pass2[pp[1]-1],
      "PASSWD_ScndPwd2" => pass2[pp[2]-1],
      "PASSWD_ScndPwd3" => pass2[pp[3]-1],
      "PASSWD_ScndPwd4" => pass2[pp[4]-1],
      "chkTrnfrCntntConf" => "on"
    }
    #p postdata
    #return nil

    res = execute('TRNTRN0508001B', postdata)
    html = res.body.toutf8

    if html =~/<div\s[^>]*id="ErrorMessage"[^>]*>(.+?)<\//
      puts $1
      raise "ERR: #{$1}"
    end

    if html =~/<span\s+id="txtRecptNo"[^>]*>([^<]+)/
      puts "recept: " + $1
      return {:receptId => $1}
    end

    nil
  end

  # _change(0, 1, 10000, "123456")
  # experimental
  def _change acc_from, acc_to, amount, pass2
    res = execute('MENSRV0100006B')
    res = execute('TRNCHN0600001B', {
      "lstDrawAccLst" => acc_from,
      "lstGiroeeAccLst" => acc_to
    })
    res = execute('TRNCHN0602001B', {
      "txbGiroAmnt" => amount
    })

    html = res.body.toutf8
    if html =~/<div\s[^>]*id="ErrorMessage"[^>]*>(.+?)<\//
      puts $1
      raise "ERR: #{$1}"
    end

    pp = []
    res.body.toutf8.scan(/<span id="txtScndPwdDgt(\d+)">(\d+)</) {|m|
      pp[$1.to_i] = $2.to_i
    }
    raise "error pass2 get digits." unless pp[1] && pp[2] && pp[3] && pp[4]

    postdata = {
      "PASSWD_ScndPwd1" => pass2[pp[1]-1],
      "PASSWD_ScndPwd2" => pass2[pp[2]-1],
      "PASSWD_ScndPwd3" => pass2[pp[3]-1],
      "PASSWD_ScndPwd4" => pass2[pp[4]-1]
    }
    #p postdata
    #return nil

    res = execute('TRNCHN0603001B', postdata)
    html = res.body.toutf8

    if html =~/<div\s[^>]*id="ErrorMessage"[^>]*>(.+?)<\//
      puts $1
      raise "ERR: #{$1}"
    end

    if html =~/<span\s+id="txtRecptNo"[^>]*>([^<]+)/
      puts "recept: " + $1
      return {:receptId => $1}
    end

    nil
  end

  # deprecated
  def zandaka
    total_balance()
  end

  private


  def _parse_history html
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

  def _parse_top html
    account_status = {}
    if html=~/<span\s+id="txtCrntBal"[^>]*>([\d,]+)/
      account_status[:total_balance] = $1.gsub(/,/,'').to_i
      account_status['zandaka'] = account_status[:total_balance]
    end

    if html=~/<span\s+id="txtLoginInfoCustNm"[^>]*>([^<]+)/
      account_status[:name] = $1
    end

    if html=~/<span\s+id="txtLastUsgTm"[^>]*>([^<]+)/
      account_status[:last_login] = $1.gsub('&nbsp;',' ')
    end

    if html=~/href=["'](\/servlet\/MENSRV0100901B.do[^"']*)/
      @logout_path = $1
    end
    account_status["recentlog"] = _parse_history(html)
    account_status
  end

  def execute page_id, postdata = {}, chk = false
    res = @client.post(@base_url + page_id + '.do', @formdata.merge(postdata))
    return nil if chk && res.status!=302
    res = @client.get(res.header['location'].first) if res.status==302
    @formdata = parse_form(res.body)
    res
  end

  def haraidashi login_html, id

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

    raise "haraidashi js not detected" unless login_html=~/=\[j,"([\w\.\-]+)","(\w+)","(\w+.js)"\]/
    url = "https://#{$1}/#{$2}/"
    js = $3
    res = @client.get(url + js)

    raise "param:dn not found" unless res.body=~/=\[s,"HsrR\.html"\]\.join\("\/"\),\w+="([0-9a-f]{2,20})"/i
    dn = $1
    raise "param:n,e not found" unless res.body=~/\{n:\s*new\s*BigInteger\("([0-9a-f]{100,})",16\),e:\s*new\s*BigInteger\("([0-9a-f]{2,20})",16\)}/i
    n = $1
    e = $2

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
    #p @client.cookies_for_host('.ib.mizuhobank.co.jp')
  end

  def sendid(res, path)
    page = $1 if path =~/\/([^\/]*)\.do/
    @formdata = parse_form(res.body)
    execute(page || 'LOGBNK0000001B', {
      "pm_fp" => "version%3D3%2E2%2E0%2E0%5F3%26pm%5Ffpua%3Dmozilla", # FingerPrint?
      "txbCustNo" => @account["ID"]
    }, true) or raise "Login failed: account id."
  end

  def sendpasswd(res)
      execute('LOGBNK0000501B', {
        "PASSWD_LoginPwdInput" => @account["PASS"]
      }, true) or raise "Login failed: passwd."
  end

  def aikotoba(res)
      raise "aikotoba fail" unless res.body=~/<span id="txtQuery">([^<]+)/
      q = $1.toutf8
      puts "AIKOTOBA? " + q
      ans = account["QA"].find {|qa| q.index(qa["q"]) }
      raise "aikotoba no_answer" unless ans
      #p ans

      execute('LOGWRD0010001B', {
        "chkConfItemChk" => "on",
        "txbTestWord" => ans['a'].tosjis
      }, true) or raise "Login failed: aikotoba."
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

  def base_url_root
    @base_url.sub('/servlet/','')
  end

end

