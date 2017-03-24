class Elasticsearch

  require 'rest-client'

  def initialize(endpoint)
    @endpoint = endpoint
    check_endpoint
  end

  def check_endpoint
    elastic_url = "http://#{@endpoint}/_cluster/health?timeout=60s&pretty"
    response    = RestClient.get(elastic_url, "Content-Type" => "application/json")
    status      = JSON.parse(response)['status']
    raise "Cluster status: #{status}" if status.eql("red")
  end

  def write_to_es(index, payload)
    index_count = get_index_count(index)
    payload.each do |item|
      index_count = index_count + 1
      add_item_to_index(item, index_count, index)
    end
  end

  def get_index_count(index)
    begin
      elastic_url = "http://#{@endpoint}/#{index}/metric/_count"
      response    = RestClient.get(elastic_url, "Content-Type" => "application/json")
      JSON.parse(response)['count']
    rescue Exception => e
      0
    end
  end

  def add_item_to_index(payload, count, index)
    begin
      url = "http://#{@endpoint}/#{index}/metric/#{count}"
      response = RestClient.post(url, payload.to_json, "Content-Type" => "application/json")
    rescue Exception => e
      puts "Response: #{response.inspect}\nEexcption: #{e.inspect}\nBacktrace: #{e.backtrace}"
    end
  end

end
