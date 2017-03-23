class Elasticsearch
   
    def initialize(endpoint)
        @endpoint = endpoint
        check_endpoint
    end
    
    def write_to_elasticsearch
     index_count = get_index_count
     @results.each do |result|
       index_count = index_count + 1
       add_item_to_index(result, index_count)
     end
    end 

    def check_endpoint
        #health check to make sure some host is healthy behind the VIP
    end
    
    def write_to_es(index)
        index_count = get_index_count
        #
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
