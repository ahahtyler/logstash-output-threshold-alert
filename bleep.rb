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
$results_array   = Array.new
$input_directory = '/home/stigty/SupBT-Metrics/src/SupBT-Metrics/input/'

def sign(request)
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
  if response.header['Content-Encoding'].eql?('gzip') then
    gz = Zlib::GzipReader.new(StringIO.new(response.body))
    response = JSON.parse(gz.read)
  else
    response = JSON.parse(response.body)
  end
  return response
end

def get(path)
  request = Net::HTTP::Get.new(path)
  sign(request)
  return parse_response($conn.request(request))
end

def create_time_ranges
  today = DateTime.now.strftime("%Y-%m-%dT08:00:00.000Z")
  day1  = (DateTime.now - 1).strftime("%Y-%m-%dT08:00:00.000Z")
  week1 = (DateTime.now - 7).strftime("%Y-%m-%dT08:00:00.000Z")
  week2 = (DateTime.now - 14).strftime("%Y-%m-%dT08:00:00.000Z")
  week3 = (DateTime.now - 21).strftime("%Y-%m-%dT08:00:00.000Z")
  week4 = (DateTime.now - 28).strftime("%Y-%m-%dT08:00:00.000Z")
  bry   = DateTime.now.strftime("%Y-01-01T08:00:00.000Z")
  bot   = "*"

  return { 'bot' => {'start' => bot  ,  'end' => today},
           '24h' => {'start' => day1 ,  'end' => today},
           '1wk' => {'start' => week1,  'end' => today},
           '2wk' => {'start' => week2,  'end' => today},
           '3wk' => {'start' => week3,  'end' => today},
           '4wk' => {'start' => week4,  'end' => today},
           'byr' => {'start' => bry  ,  'end' => today}}
end

def create_label_combos
  $supBT_labels    = {
      "SupBT"   => "a5739bf8-3339-4a66-94d9-484b5287dfb9",
      "Handoff" => "f15cb04c-633f-4a42-95f5-110b99b6cbc8",
      "SysEng"  => "6231cdee-5f96-45f4-83ec-9daec101f8fd"
  }

  label_combos = $supBT_labels
  label_combos["No Labels"]  = $supBT_labels.values.join(" OR ")
  label_combos["All Labels"] = ""
  return label_combos
end

def has_parent_folder?(guid)
  folder = get("/folders/#{guid}")
  folder['parent'].nil? ? true : false
end

def build_payload(fguid, searchType, timeframe, reqs, label_key, label_guid)

  exclude_labels, exclude_folders = reqs['ignoreLabels'], reqs['ignoreFolders']
  payload = ""

  #Constant fields across all searches
  payload += "folderType:(Default)"

  #Setting folder search field
  has_parent_folder?(fguid) ? payload += "assignedFolder:" : payload += "containingFolder:"
  payload += "(#{fguid})"

  #Setting Time Range
  searchType.eql?("Resolved") ? payload += "lastResolvedDate:" : payload += "createDate:"
  payload += "[#{timeframe['start']} TO #{timeframe['end']}]"

  #Set Status
  payload += "status:(Open)"     if ["Open", "Actionable"].include?(searchType)
  payload += "status:(Resolved)" if ["Resolved"].include?searchType

  #Optional fields
  payload += "-containingFolder:(#{exclud_labels.join(" OR ")})" unless exclude_labels.empty?

  #Set up labels
  payload += "aggregatedLabels:(#{label_guid})" if ["SupBT", "Handoff", "SysEng"].include?(label_key)

  if exclude_labels.empty?
    if label_key.eql?("No Labels")
      payload += "-aggregatedLabels:(#{label_guid})"
    end
  else
    if label_key.eql?("No Labels")
      payload += "-aggregatedLabels:(#{exclude_labels.join(" OR ")} OR #{label_guid})"
    else
      payload += "-aggregatedLabels:(#{exclude_labels.join(" OR ")}"
    end
  end

  payload += "next_step.owner:role\\:resolver" if searchType.eql?("Actionable")
  return payload
end

def build_query(payload)
  #encode Payload
  payload = CGI.escape payload

  #Add sort
  sort = "sort=lastUpdatedConversationDate+desc"
  sort = CGI.escape sort

  return "/issues?q=#{payload.gsub("+","%20")}&#{sort}"
end

def sev2_issues_search(dates, folders, exclude_labels, exclude_folders)
  #Search Top level folder
  #Include subfolder
  #Search for sev2.
end

def create_hash(team, dateKey)
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

def backoff
   @backoff = 0  if @backoff.nil?
   @backoff += 1 if @backoff < 10
   sleep @backoff ** 2
end
    
begin
  #Read in input
  input = read_input

  #determine date array
  dateHash = create_time_ranges

  #determine label combos
  labelHash = create_label_combos

  input.each do |team, reqs|
    reqs['folders'].each_with_index do |folderGuid, index|
      dateHash.each do |timeKey, timeRange|
        labelHash.each do |labelKey, labelGuid|
          ["New Issue", "Open", "Resolved", "Actionable"].each do |searchType|
            #puts "#{team} --- #{timeKey} --- #{timeRange} --- #{labelKey} --- #{searchType}"
            payload = build_payload(folderGuid, searchType, timeRange, reqs, labelKey, labelGuid)
            begin
                issue = get(build_query(payload))
                raise if issue['message'].eql?("Rate exceeded")
            rescue
                backoff
                retry  
            end
            puts "issues: #{issue['totalNumberFound']}"
            $results_array.push(create_hash(timeKey, team))
          end
        end
      end
    end
  end

    #Write to CSV

    #Write to ElasticSearch

rescue Exception => e
  puts "Error"
end
