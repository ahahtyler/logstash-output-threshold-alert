require 'amazon/sim'
require 'aws-sdk-for-ruby'
require 'date'
require_relative 'lib/elasticsearch.rb'
require_relative 'lib/maxis_connection.rb'

require 'rest-client'
require 'json'

TODAY = Time.parse(DateTime.now.to_s)
YESTERDAY = Time.parse((DateTime.now - 7).to_s)

puts TODAY
puts YESTERDAY

materialSet = 'com.amazon.credentials.isengard.968648960172.user/stigty'
credentials = Aws::OdinCredentials.new(materialSet)
sim = Amazon::SIM.new( :region => 'us-west-2',
					   :access_key_id => credentials.access_key_id,
					   :secret_access_key => credentials.secret_access_key)

issues = sim.issues.filters(:containingFolder => ["f8f2a971-ecdb-4551-aed1-744f9204d378"],
							:createDate => [YESTERDAY, TODAY])

count = 0
new_issues = Array.new
issues.each do |i|
	puts "ID #{i.id}"
	puts "Created: #{i.created}"
	puts "Folder: #{i.folder.name}"
	puts "Submitter: #{i.submitter}"
	es_data_point ={ 'issue_id'      => i.id ,
                     'folder_name'   => "" ,
                     'folder_guid'   => "" ,
					 'touched'       => false,
					 'first_touched' => "" ,
					 'create_date'   => i.created,
					 'touch_time'    =>  "" ,
                     '@timestamp'    => DateTime.now}
	
	new_issues.push(es_data_point)
	break;
end

@es_server   = "supbtsearch.corp.amazon.com"
@es_index    = "count_metrics_test"

elastic = Elasticsearch.new(@es_server)
#TODO: Write if not duplicate
elastic.write_to_index(@es_index, new_issues)

elastic_url = "http://#{@es_server}/#{@es_index}/_search?q=touched:false"
response    = RestClient.get(elastic_url, "Content-Type" => "application/json")
response = JSON.parse(response)['hits']['hits']

@host        = 'maxis-service-prod-pdx.amazon.com'
@scheme      = 'https'
@region      = 'us-west-2'
@materialSet = 'com.amazon.credentials.isengard.968648960172.user/stigty'
@maxis = MaxisConnection.new(@host, @scheme, @region, @materialSet)

response.each do |r|
	issue_id = r["_source"]["issue_id"]
	puts issue_id
	edits = @maxis.get("/issues/#{issue_id}/edits")
	edits["edits"].each do |e|
		puts "Actor: #{e["actualOriginator"]}"
		puts "Time: #{e["actualCreateDate"]}"
		e["pathEdits"].each do |p|
			puts "---Action: #{p["path"]}"
		end
	end
	
	elastic_url = "http://#{@es_server}/#{@es_index}/metric/#{r["_id"]}/_update"
	puts elastic_url
	payload = {
				"doc" => {
							"touched" => true
						 }
				}
	
	response = RestClient.post(elastic_url, payload.to_json, "Content-Type" => "application/json")	
	puts response
	break;
end



#Query ES for non-touched issues
#Loop through Nontouched issues
  # Query SIM for edit history
  # Query SIM/TT for resolver groups
  # Loop through edit history
    # Find create date
    # Find comment date by resolver
    # If comment dat by resolver is found
      # Update ES item touched = true


#Store
# {
#   issue_id      - String
#   issue_guid    - String
#   folder_name   - String
#   folder_guid?  - String
#   touched       - boolean
#   first_touch   - DateTime
#   create_date   - DateTime
#   touch_time    - Int (minutes)
#   @timestamp    - DateTime
# }


###ES Methods
#Query(index, payload)
#Update item(index, payload, itemNumber)
