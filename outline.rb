require 'amazon/sim'
require 'aws-sdk-for-ruby'
require 'date'
require_relative 'lib/elasticsearch.rb'
require_relative 'lib/maxis_connection.rb'

require 'rest-client'
require 'json'

def initialize_sim_api
  materialSet = 'com.amazon.credentials.isengard.968648960172.user/stigty'
  credentials = Aws::OdinCredentials.new(materialSet)
  return Amazon::SIM.new( :region            => 'us-west-2',
                          :access_key_id     => credentials.access_key_id,
                          :secret_access_key => credentials.secret_access_key)
end

def create_team_list
  teamHash = Hash.new()

  team_block = @doc.css("team_config/service_line")
  team_block.map do |service|
    subfolderHash = Hash.new()
    service.css("folder_group").map do |subfolder|
      guidArray = Array.new()
      subfolder.css("guid").map do |guid|
        guidArray.push(guid.children.to_s)
      end
      subfolderHash[subfolder["name"]] = guidArray
    end

    ignoreFolderArrray = Array.new()
    ignoreLabelsArray = Array.new()

    service.css("ignore").map do |item|
      ignoreFolderArrray.push(item["guid"]) if item["type"].eql?("folder")
      ignoreLabelsArray.push(item["guid"])  if item["type"].eql?("label")
    end
    teamHash[service["name"]] = {'groups' => subfolderHash, 'ignoreF' => ignoreFolderArrray, 'ignoreL' => ignoreLabelsArray}
  end
  return teamHash
end

def generate_es_input(issues)
  new_issues = Array.new
  issues.each do |i|
    es_data_point ={ 'issue_id'      => i.id ,
                     'create_date'   => i.created,
                     'touched'       => false,
                     '@timestamp'    => @today,
                     'folder_name'   => "",
                     'first_touched' => "",
                     'time_open'    => ""}
    #maybe add a label here
    new_issues.push(es_data_point)
  end
  return new_issues
end

def get_es_results(index, payload)
  elastic_url = "http://#{@es_server}/#{index}/_search?q=#{payload}"
  response    = RestClient.get(elastic_url, "Content-Type" => "application/json")
  response = JSON.parse(response)['hits']['hits']
  return response
end

def update_es_item(index, key, value, id)
  elastic_url = "http://#{@es_server}/#{index}/metric/#{id}/_update"
  puts elastic_url
  payload = {
      "doc" => {
          key => value
      }
  }
  response = RestClient.post(@elastic_url, payload.to_json, "Content-Type" => "application/json")
end

def find_resolvers(teamHash)
  {"CS Guid" => ["stigty"],
   "ACDC guid" => ["stigty"] }
  #for each team
    #for each folder
      #Find resolvers on folder
      #Find members on resolver group
    #end
  #end
end

@host        = 'maxis-service-prod-pdx.amazon.com'
@scheme      = 'https'
@region      = 'us-west-2'
@materialSet = 'com.amazon.credentials.isengard.968648960172.user/stigty'

@es_server = "supbtsearch.corp.amazon.com"
@es_index  = "count_metrics_test"

@today     = Time.parse(DateTime.now.strftime("%Y-%m-%dT08:00:00.000Z").to_s)
@yesterday = Time.parse((DateTime.now - 1).strftime("%Y-%m-%dT08:00:00.000Z").to_s)

maxis   = MaxisConnection.new(@host, @scheme, @region, @materialSet)
elastic = Elasticsearch.new(@es_server)

teamHash     = create_team_list
resolverHash = find_resolvers(teamHash)
sim_conn     = sintialize_sim_api

#for each team
  #for each folder
   issues = sim_conn.issues.filters(:containingFolder => [folder.guid],
                                    :createDate       => [@yesterday, @today])
   issue_items = generate_es_input(issues)
  #end
#end

elastic.write_to_index(@es_index, issue_items)
es_results = get_es_results(@es_index, "touched:false")

es_results.each do |r|
  issue_id = r["_source"]["issue_id"]
  edits = maxis.get("/issues/#{issue_id}/edits")
  edits["edits"].each do |e|
    puts "Actor: #{e["actualOriginator"]}"
    puts "Time: #{e["actualCreateDate"]}"
    e["pathEdits"].each do |p|
      puts "---Action: #{p["path"]}"
      #Get folder GUID

      #if path == comment && resolver["GUID"].include?(actorOriginator)
        update_es_item(@es_index,"touched", "true", r["_id"])
        update_es_item(@es_index, "folder_name", r["folder"], r["_id"])
        update_es_item(@es_index, "first_touched", ftt, r["_id"])
        update_es_item(@es_index, "open_time", time_in_sec, r["_id"])
      #else
         #figure out how long ticket has been open and update open_time
      #end

    end
  end


end

