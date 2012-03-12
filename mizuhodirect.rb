#
#  みずほダイレクトβ
#    http://www.binzume.net/
require "kconv"
#require "hpricot"
require "rexml/document"

class MizuhoDirect
  attr_accessor :account, :account_status

  def initialize(account = nil)
    @account_status = {
      "zandaka" => nil,
      "recentlog" => nil,
    }
    if account
      login(account)
    end
  end

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

  def logout
    unless @login_success
      return
    end
    return @client.get('https://'+@host+'/servlet/mib?xtr=EmfLogOff');
  end

  def get_top
    unless @login_success
      return
    end
    res = @client.get('https://'+@host+'/servlet/mib?xtr=Emf02000')
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
    account_status["recentlog"] = recent
    return account_status

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
    account_status["recentlog"] = recent

    @account_status = account_status
    return account_status
  end

  def zandaka
    @account_status['zandaka']
  end

end

