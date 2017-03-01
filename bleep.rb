require 'aws-sdk-core'
require 'aws/odin_credentials'
require 'json'
require 'amazon/cacerts'
require 'amazon/sim'
require 'date'

$host        = 'maxis-service-prod-pdx.amazon.com'
$scheme      = 'https'
$region      = 'us-west-2'
$materialSet = 'com.amazon.credentials.isengard.968648960172.user/stigty'

$conn             = Net::HTTP.new($host, 443)
$conn.use_ssl     = true
$conn.verify_mode = OpenSSL::SSL::VERIFY_PEER

store = OpenSSL::X509::Store.new
store.set_default_paths
$conn.cert_store  = store

$credentials = Aws::OdinCredentials.new($materialSet)
$signer      = Aws::Signers::V4.new($credentials, 'sim', $region)

$run_id          = SecureRandom.uuid.gsub('-','')
$metrics_array   = Array.new
$input_directory = '/home/stigty/SupBT-Metrics/src/SupBT-Metrics/input/' 
$const_labels    = {
    "SupBT"   => "a5739bf8-3339-4a66-94d9-484b5287dfb9",
    "Handoff" => "f15cb04c-633f-4a42-95f5-110b99b6cbc8",
    "SysEng" => "6231cdee-5f96-45f4-83ec-9daec101f8fd",
    "No Labels" => "a5739bf8-3339-4a66-94d9-484b5287dfb9 OR f15cb04c-633f-4a42-95f5-110b99b6cbc8 OR 6231cdee-5f96-45f4-83ec-9daec101f8fd"
 }
  
# @param [Net::HTTP::Request] request the request to sign (modified in place)
def sign(request)
  # Convert Net::HTTP::Request to Seahorse::Client::Http::Request, use the v4 signer, then
  # overwrite the original request
  seahorseRequest = Seahorse::Client::Http::Request.new(
    :endpoint => "#{$scheme}://#{$host}#{request.path}",
    :http_method => request.method,
    :body => request.body
  )

  request.each_header {|key,value| seahorseRequest.headers[key] = value}
  $signer.sign(seahorseRequest)
  seahorseRequest.headers.each {|key,value| request[key] = value}
end
 
def parse_response(response)
  # Check response encoding and decode if gzip since Net::HTTP.request seems
  # to not automatically handle response encoding like Net::HTTP.get does.
  if response.header['Content-Encoding'].eql?('gzip') then
    gz = Zlib::GzipReader.new(StringIO.new(response.body))
    response = JSON.parse(gz.read)
  else
    response = JSON.parse(response.body)
  end
  return response
end
 
# Issue a GET request against maxis-service expecting JSON in response
def get(path)
  request = Net::HTTP::Get.new(path)
  sign(request)
  return parse_response($conn.request(request))
end    
    
def createDateArray
    today = DateTime.now.strftime("%Y-%m-%dT08:00:00.000Z")
    day1  = (DateTime.now - 1).strftime("%Y-%m-%dT08:00:00.000Z")
    week1 = (DateTime.now - 7).strftime("%Y-%m-%dT08:00:00.000Z")
    week2 = (DateTime.now - 14).strftime("%Y-%m-%dT08:00:00.000Z")
    week3 = (DateTime.now - 21).strftime("%Y-%m-%dT08:00:00.000Z")
    week4 = (DateTime.now - 28).strftime("%Y-%m-%dT08:00:00.000Z")
    yearold  = DateTime.now.strftime("%Y-01-01T08:00:00.000Z")
    forever  = "*"    

    return [ { 'start' => day1,    'end' => today},    
             { 'start' => week1,   'end' => today},    
             { 'start' => week2,   'end' => week1},    
             { 'start' => week3,   'end' => week2},    
             { 'start' => week4,   'end' => week3},    
             { 'start' => yearold, 'end' => today}, 
             { 'start' => forever, 'end' => today} ]        
end    
    
def build_payload(guid, index, searchType, timeframe, exclude_labels, exclude_folders)
    
    if index == 0
        payload = "assignedFolder:(#{guid})"
    else
        payload = "containingFolder:(#{guid})"
    end
    
    payload += "-containingFolder:(#{exclude_folders.join(" OR ")})" unless exclude_folders.empty?
    payload += "folderType:(Default)"
    
    case searchType
    when "Open", "Actionable", "New Issue"
        payload += "status:(Open)"
        payload += "createDate:[#{timeframe["start"]} TO #{timeframe["end"]}]"
    when "Resolved"
        payload += "status:(Resolved)"
        payload += "lastResolvedDate:[#{timeframe["start"]} TO #{timeframe["end"]}]"
    end

    paylaod += "-aggregatedLabels:(#{exclude_labels.join(" OR ")})" unless exclude_labels.empty?

    
    return payload
end    
    
def set_labels(label, guid, exclude_labels)
    payload = ""
    if exclude_labels.empty?
        if label.eql?("No Labels")
            payload += "-aggregatedLabels:(#{guid})"
        else
            payload += "aggregatedLabels:(#{guid})"    
        end
    else
        if label.eql?("No Labels")
            paylaod += "-aggregatedLabels:(#{exclude_labels.join(" OR ")} OR #{guid})" 
        else
            paylaod += "-aggregatedLabels:(#{exclude_labels.join(" OR ")})"
            payload += "aggregatedLabels:(#{guid})"
        end
    end
    return payload
end
    
def new_issues_search(dates, reqs)
    reqs['folders'].each_with_index do |guid, index|
        puts "guid: #{guid}"
        dates.each do |timeframe|
            #puts "timeframe: #{timeframe}"
            #Create payload
            payload = build_payload(guid, index, "New Issue", timeframe, reqs['ignoreLabels'], reqs['ignoreFolders'])

            #encode Payload
            payload = CGI.escape payload

            #Add sort
            sort = "sort=lastUpdatedConversationDate+desc"
            sort = CGI.escape sort

            #Call Maxis
            issue = get("/issues?q=#{payload.gsub("+","%20")}&#{sort}")

            puts "issues: #{issue['totalNumberFound']}"
        end
    end
end
    
def open_issues_search(dates, reqs)
    reqs['folders'].each_with_index do |guid, index|
        puts "guid: #{guid}"
        dates.each do |timeframe|
            #puts "timeframe: #{timeframe}"
            $const_labels.each do |label, lguid|
                #puts "label: #{label}"
                #Create payload
                payload = build_payload(guid, index, "Open", timeframe, reqs['ignoreLabels'], reqs['ignoreFolders'])
                payload += set_labels(label, lguid, exclude_labels)
                
                #encode Payload
                payload = CGI.escape payload
                
                #Add sort
                sort = "sort=lastUpdatedConversationDate+desc"
                sort = CGI.escape sort

                #Call Maxis
                issue = get("/issues?q=#{payload.gsub("+","%20")}&#{sort}")
                puts "issues: #{issue['totalNumberFound']}"
            end
        end
    end
end
    
def resolved_issues_search(dates, reqs)
    reqs['folders'].each_with_index do |guid, index|
        puts "guid: #{guid}"
        dates.each do |timeframe|
            #puts "timeframe: #{timeframe}"
            
            $const_labels.each do |label, lguid|
                #puts "label: #{label}"
                #Create payload
                            
                payload = build_payload(guid, index, "Resolved", timeframe, reqs['ignoreLabels'], reqs['ignoreFolders'])
                payload += set_labels(label, lguid, exclude_labels)

                #encode Payload
                payload = CGI.escape payload
                
                #Add sort
                sort = "sort=lastUpdatedConversationDate+desc"
                sort = CGI.escape sort

                #Call Maxis
                issue = get("/issues?q=#{payload.gsub("+","%20")}&#{sort}")

                puts "issues: #{issue['totalNumberFound']}"
            end
        end
    end
end
    
def actionable_issues_search(dates, reqs)
    reqs['folders'].each_with_index do |guid, index|
        puts "guid: #{guid}"
        dates.each do |timeframe|
            #puts "timeframe: #{timeframe}"
            
            $const_labels.each do |label, lguid|
                #puts "label: #{label}"
                #Create payload
                payload = build_payload(guid, index, "Actionable", timeframe, reqs['ignoreLabels'], reqs['ignoreFolders'])
                payload += set_labels(label, lguid, exclude_labels)
                payload += "next_step.owner:role\\:resolver"

                puts payload
                
                #encode Payload
                payload = CGI.escape payload

                #Add sort
                sort = "sort=lastUpdatedConversationDate+desc"
                sort = CGI.escape sort

                #Call Maxis                
                issue = get("/issues?q=#{payload.gsub("+","%20")}&#{sort}")

                puts "issues: #{issue['totalNumberFound']}"
            end
        end
        break;
    end

end

def sev2_issues_search(dates, folders, exclude_labels, exclude_folders)
   #Search Top level folder
   #Include subfolder
   #Search for sev2. 
end

def create_hash
    #{
    #    count       => int     (1,2,3, etc...)
    #    team        => string  (Deploy, Brazil, QTT, etc...)
    #    folder_name => string  (PBS, SIM, ACDC, etc...)
    #    folder_guid => string  (asdf-asff-asdf, etc...)
    #    search_type => string  (new, open, actionable, resolved)
    #    label       => string  (supbt, handoff, none)
    #    runid       => string  (zxcv-zxcv-xzcv, etc...)
    #    sim_query   => string  (https://issues.amazon.com....)
    #    timeframe   => string  (day, week1, week2, week3, week4, month, bot)
    #}
end

def read_file(filename)
    input_array = Array.new
    File.open("#{$input_directory}/#{filename}", "r") do |f|
        f.each_line do |line|
            input_array.push(line.strip)
        end
    end
    return input_array
end

def read_input
    team_hash = Hash.new{|hsh,key| hsh[key] = {} }
    Dir.foreach($input_directory) do |item|
      next if item == '.' or item == '..' 
        file_parse = item.split('-')
        team_hash[file_parse[0]].store file_parse[1][0..-5],read_file(item)
    end
    return team_hash
end
    
#---begin

#Read in input
input = read_input

#Validate GUIDS

#determine date array
dateArray = createDateArray
    
input.each do |team, reqs|
    
    #new_issues_search(dateArray, reqs)
    #open_issues_search(dateArray, reqs)
    #resolved_issues_search(dateArray, reqs)
    actionable_issues_search(dateArray, reqs)
    #sev2_issues_search(dateArray, reqs['folders'], reqs['ignoreLabels'], reqs['ignoreFolders'])
        
end

#Do Overall searches
    #New Issues:      [now - 1]
    #Open Issues:     [SupBT, Handoff, None], [now - beginning of time], [now - beginning of year]
    #Resolved Issues: [SupBT, Handoff, None], [now - 1], [now - beginning of year]

#Write to CSV

#Write to ElasticSearch
