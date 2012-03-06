require 'uri'
require 'net/https'
Net::HTTP.version_1_2

class HTTPClient
  def initialize opt = nil
    @cookies = {}
    @timeout = 60
    if opt && opt[:agent_name]
      @agent_name = opt[:agent_name]
    end
  end
  attr_accessor :timeout, :cookies

  def formencode data
    return data.map{|k,v| k+'='+URI.encode(v.to_s)}.join('&')
  end

  def pre_proc uri,headers = nil
    headers = headers || {}
    if @cookies[uri.host]
      headers['Cookie'] = @cookies[uri.host].map{|k,v|k+'='+v}.join(';')
    end
    if @agent_name
      headers['User-Agent'] = @agent_name
    end
    http = Net::HTTP.new(uri.host,uri.port)
    http.read_timeout = @timeout
    if uri.scheme == 'https'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    return http,headers
  end

  def post_proc uri,response
    if response['Set-Cookie']
      if ! @cookies[uri.host]
        @cookies[uri.host] = {}
      end
      response.get_fields('Set-Cookie').each{|str|
        k,v = (str.split(';'))[0].split('=')
        @cookies[uri.host][k] = v
      }
    end
    def response.status
      response.code.to_i
    end
    def response.header
      headers = {}
      response.each{|header,value|
        headers[header] = [value]
      }
      return headers
    end
    return response
  end

  def get url,headers = nil,&block
    uri = URI.parse(url)
    http,headers = pre_proc(uri,headers)
    r = http.get(uri.request_uri,headers,&block)
    return post_proc(uri,r)
  end
  
  def get_content url,headers = nil
    r = get(url,headers)
    return r.body
  end

  def post url,body,headers = nil,&block
    uri = URI.parse(url)
    http,headers = pre_proc(uri,headers)

    if body.kind_of? Hash
      body = formencode(body)
    end
    if headers['Content-Type'] == nil
      headers['Content-Type'] = 'application/x-www-form-urlencoded'
    end
    r = http.post(uri.request_uri,body,headers,&block)
    return post_proc(uri,r)
  end

  def put url,body,headers = nil,&block
    uri = URI.parse(url)
    http,headers = pre_proc(uri,headers)

    if body.kind_of? Hash
      body = formencode(body)
    end

    if headers['Content-Type'] == nil
      headers['Content-Type'] = 'application/x-www-form-urlencoded'
    end
    r = http.start() do
      return http.__send__(:put, uri.request_uri, body, headers)
    end
    return post_proc(uri,r)
  end

  def request req_class, url, body = nil, &block
    if req_class == Net::HTTP::Get
      return get(url,nil,&block)
    else
      return post(url,body,nil,&block)
    end
  end
end
