class MaxisConnection
  require 'aws-sdk-core'
  require 'aws/odin_credentials'
  require 'json'
  require 'amazon/cacerts'

  def initialize(host, region, materialSet)
    @host        = host
    @scheme      = 'https'
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
      raise "Rate exceeded" if response['message'].eql?("Rate exceeded")
      return response
    rescue Exception => e
      if (e.to_s).eql?("Rate exceeded")
        backoff
        retry
      else
        puts "Error calling maxis: #{e}\n\nBacktrace: #{e.backtrace}"
      end
    end
  end

  def post(path, content)
    begin
      request = Net::HTTP::Post.new(path)
      request.body = content.to_json()
      request.content_type = "application/json"
      sign(request)
      response = parse_response(@conn.request(request))
      raise "Rate exceeded" if response['message'].eql?("Rate exceeded")
      puts "Maxis Response: #{response}"
      return response
    rescue Exception => e
      if (e.to_s).eql?("Rate exceeded")
        backoff
        retry
      else
        puts "Error calling maxis: #{e}\n\nBacktrace: #{e.backtrace}"
      end
    end
  end

  def backoff
    puts "Throttle limit reached. Backing off 30 seconds"
    sleep 30
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
