class MaxisConnection
  require 'aws-sdk-core'
  require 'aws/odin_credentials'
  require 'json'
  require 'amazon/cacerts'
  require 'amazon/sim'

  def initialize(host, scheme, region, materialSet)
    @host        = host
    @scheme      = scheme
    @region      = region
    @materialSet = materialSet

    @conn             = Net::HTTP.new(@host, 443)
    @conn.use_ssl     = true
    @conn.verify_mode = OpenSSL::SSL::VERIFY_PEER

    store = OpenSSL::X509::Store.new
    store.set_default_paths
    @conn.cert_store  = store

    @credentials = Aws::OdinCredentials.new(@materialSet)
    @signer      = Aws::Signers::V4.new(@credentials, 'sim', @region)
  end

  def sign(request)
    seahorseRequest = Seahorse::Client::Http::Request.new(
        :endpoint => "#{@scheme}://#{@host}#{request.path}",
        :http_method => request.method,
        :body => request.body
    )
    request.each_header {|key,value| seahorseRequest.headers[key] = value}
    @signer.sign(seahorseRequest)
    seahorseRequest.headers.each {|key,value| request[key] = value}
  end

  def parse_response(response)
    if response.header['Content-Encoding'].eql?('gzip') then
      gz = Zlib::GzipReader.new(StringIO.new(response.body))
      response = JSON.parse(gz.read)
    else
      response = JSON.parse(response.body)
    end
    return response
  end

  def get(path)
    begin
      request = Net::HTTP::Get.new(path)
      sign(request)
      response = parse_response(@conn.request(request))
      raise if response['message'].eql?("Rate exceeded")
      return response
    rescue
      backoff
      retry
    end
  end

  def backoff
    @backoff = 0  if @backoff.nil?
    @backoff += 1 if @backoff < 10
    sleep @backoff ** 2
  end

  def encode(payload)
    #encode Payload
    payload = CGI.escape payload

    #Add sort
    sort = "sort=lastUpdatedConversationDate+desc"
    sort = CGI.escape sort

    return "/issues?q=#{payload.gsub("+","%20")}&#{sort}"
  end

end
