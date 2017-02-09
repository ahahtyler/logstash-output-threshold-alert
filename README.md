```
require "open3"
require "csv"
require "json"
require "uri"
require "date"

def debug(msg)
   puts msg if @debug 
end

#Parse a CSV file to return array of hashes
def normalize_csv(csv_path)
    csv_array = Array.new
    
    begin
        CSV.foreach(csv_path, :headers => true) do |row|
            csv_item = {'url' => row['url'], 'search' => row['search'], 'category' => row['category'], 'count' => Array.new}
            csv_array.push(csv_item)
        end
    rescue Exception => e
        puts "Error: #{e.inspect} - Backtrace: #{e.backtrace}"
    end
    
    csv_array
end

#Parse out the SIM search paramaters from input URL
private
def find_sim_search_params(url)
    
    issue_search_url = "https://issues.amazon.com/issues/search?q="    
    sim_search_url = "https://sim.amazon.com/issues/search?q="
    
    if url.include?(issue_search_url)
        search_url = issue_search_url
    elsif url.include?(sim_search_url)
        search_url = sim_search_url
    else
        raise "invalid URL"
    end
    
    decode = URI.decode(url)
    raw_search_params = decode[search_url.length..-1]
    raw_search_params_array = raw_search_params.scan(/-?[a-zA-Z]*:\([^);]+\)/)

    search_params_array = Array.new
    raw_search_params_array.each do |param|
        search_item = param.tr(')','').split(':(')
        param_hash = {'key' => search_item[0], 'value' => search_item[1]}
        search_params_array.push(param_hash)
    end

    #puts search_params_array.inspect

    search_params_array
end

#Map SIM search params to a maxis search
private 
def create_maxis_query(search_params)
    
    maxis_begin = "issues?q="
    maxis_end = "sort=lastUpdatedConversationDate+desc&rows=500&omitPath=conversation&maxis%3Aheader%3AAmzn-Version=1.0"
    maxis_search = ""
    
    search_params.each_with_index do |x, index|
        
        sim_key, sim_value = x['key'], x['value']
        
        begin
            case sim_key
            when "-label"
                maxis_key = "-aggregatedLabels"
                maxis_value = "(#{sim_value})"
            when "label"
                maxis_key = "aggregatedLabels"
                maxis_value = "(#{sim_value})"
            when "nextStepOwner"
                maxis_key = "next_step.owner%3Arole%5C"
                maxis_value = sim_value.downcase           
            when "-nextStepOwner"
                maxis_key = "-next_step.owner%3Arole%5C"
                maxis_value = sim_value.downcase           
            when "title", "-title"
                maxis_key = sim_key
                maxis_value = "(%22#{sim_value.tr('\"', '')}%22)"
            when "containingFolder", "-containingFolder", "assignedFolder", "-assignedFolder"
                maxis_key = sim_key
                maxis_value = "(#{sim_value})"
            when "folderType", "-folderType"
                maxis_key = sim_key
                maxis_value = sim_value
            when "status", "-status"
                maxis_key = sim_key
                maxis_value = sim_value
            when "assignee", "-assignee"
                maxis_key = sim_key
                maxis_value = sim_value
            when "folderType", "-folderType"
                maxis_key = sim_key
                maxis_value = sim_value
            when "createDate" , "-createDate", "lastResolvedDate", "-lastResolvedDate"
                maxis_key = sim_key
                date_array = sim_value.tr('[]', '').split('..')
                if date_array[0].empty?
                    maxis_value = "%5B*+TO+#{@today.gsub(":", "%3A")}%5D"
                else 
                    maxis_value = "%5B#{@last_week.gsub(":", "%3A")}+TO+#{@today.gsub(":", "%3A")}%5D"
                end  
            else
                raise "SIM Key: #{sim_key} - SIM value: #{sim_value} could not be matched. Skipping..."
            end

            maxis_search = maxis_search + maxis_key + "%3A" + maxis_value + (index == search_params.size - 1 ? "&" : "+AND+")
            
        rescue Exception => e
            puts "Error: #{e.inspect} - Backtrace: #{e.backtrace}"
        end
    end
    
    full_maxis_url = maxis_begin + maxis_search + maxis_end
end

#Form the curl command
private 
def curl(url, query)     
    full_url = "#{url}/#{query}"
    serenity_flags = "-g --anyauth --location-trusted -u: -c cookies.txt -b cookies.txt -v --capath /apollo/env/SDETools/etc/cacerts -sS"
    cmd = "curl #{serenity_flags} \"#{full_url}\""
    bash(cmd)
end

#Run input paramater on linux console
private 
def bash(cmd)
    #stdout, stderr, status = Open3.capture3("timeout 10 #{cmd}")
    
    #puts cmd
    
    stdout, stderr, status = Open3.capture3("#{cmd}")
    command_output = {:stdout => valid_json?(stdout), :stderr => stderr, :status => status.success?}
    
    #puts command_output[:stderr]
    
    command_output
end

private
def valid_json?(stdout)

    begin
      JSON.parse(stdout)
    rescue Exception => e
      stdout
    end

end 

#write parameters to a csv file
private
def write_to_csv(output, results)
    CSV.open(output, "wb") do |csv|
        results.each do |val|
            
            #puts "---------------"
            #puts val.inspect if val['count'].map(&:to_i).max.nil?
            #puts "---------------"
            
            csv << [val['category'], val['search'], val['count'].map(&:to_i).max, val['url']]
        end
    end
end

begin
        
    @debug = false
    
    #Date math to figure out what time to use
    # @today = DateTime.now.strftime("%Y-%m-%dT00:00:00.000Z")
    # @last_week = (DateTime.now - 7).strftime("%Y-%m-%dT00:00:00.000Z")

    @today = "2017-02-03T08:00:00.000Z"
    @last_week = "2017-01-27T08:00:00.000Z"    

    puts @today
    puts @last_week
    
    #Location of input and output csv files
    input = "/home/stigty/supbt-metrics/src/SupBT-Metrics/input.csv"
    output = "/home/stigty/supbt-metrics/src/SupBT-Metrics/out.csv"

    #Maxis web service endpoints    
    endpoints = ["https://maxis-service-prod-iad.amazon.com/",
                 "https://maxis-service-prod-pdx.amazon.com/", 
                 "https://maxis-service-prod-dub.amazon.com/"]
    
    #Parse input CSV into array of hash values
    input_array = normalize_csv(input)
        
    #puts "Input Array: #{input_array}"
    
    unless input_array.empty?
        input_array.each do |search|
            
            #Parse SIM query
            search_params = find_sim_search_params(search['url'])            
            raise "Search Params Array was empty" if search_params.empty? 
            
            #Map SIM query to Maxis Query
            maxis_query = create_maxis_query(search_params)
            search['maxis'] = maxis_query
            
            debug("Maxis Query: #{maxis_query}")
            
            #Curl all maxis endpoints
            endpoints.each do |url| 
                curl_output = curl(url, maxis_query)
                #debug("Curl Output: #{curl_output.inspect}")
                search['count'].push(curl_output[:stdout]["totalNumberFound"]) 
            end
            
            debug("Search Hash: #{search.inspect}")
            
            puts "#{search['category']} ---- #{search['search']} ---- #{search['count'].inspect}"
            
            #sleep 10
        end
        
        #Write output to CSV
        write_to_csv(output, input_array)
    else
        puts "Input array was empty. Cannot continue: #{input_array.inspect}"
    end
    
rescue Exception => e
    puts "Exception: #{e.inspect}"
    puts "Backtrace: #{e.backtrace}"
end
```
