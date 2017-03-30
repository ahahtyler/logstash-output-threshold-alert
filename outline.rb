#Pull issues created yesterday

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

#Search Through ES for touched = false

#For each value returned in search (hopefully an ES object)
  # Query SIM for edit history
  # Query SIM/TT for resolver groups
  # Loop through edit history
    # Find create date
    # Find comment date by resolver
    # If comment dat by resolver is found
      # Update ES item touched = true

###ES Methods
#Query(index, payload)
#Update item(index, payload, itemNumber)
