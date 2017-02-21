# logstash-output-threshold-alert


SIM Query Parameter Breakdown
Label            - SupBT, SupBT Handoff, SysEng      	- Non-application specific
NextStepOwner    - Resolver, Requester       			- Non-application specific
createDate       - 24hr, 7days, 10days, 30days			- Non-application specific
lastResolvedDate - 24hr, 7days, 10days, 30days 	        - Non-applicatoin specific
status           - Open, Resolved					 	- Non-application specific
folderType       - Default					  		    - Non-application specific
** Not present everywhere. Need to determine relevance.
assignee         - nobody						  		- Non-application specific
** Only present in one search Query

Containing Folder(include subfolders)      - Application specific
Assigne Folder (don't include subfolders)  - Application specific
Title - "Unlicensed+Remedy+host"           - Application specific
** Only Present on SWIM

Required INPUT
Folder-GUIDS-Include
- Need TopLevel Folder -> Sub Folder Hiearchy           		
Folder-GUIDS-Exclude  
- Need TopLevel Folder -> Sub Folder Hiearchy
Label-GUIDS-For-Search
- SupBT, SupBT Handoff, SysEng

Basic Searches - Overall Status
- New Issues Created
- Resolved Issues
- Open Issues

Basic Searches - For Application Team
- New Issues Created Over 24hr
- Open Issues from beginning of time to now
- Resolved issues over 24hr 
- Actionalbe Tickets
- Issues Handed Off
- Open Issues created this week
- Open Issues created < 1 Month
- Open Issues created > 1 Month
- Open Actionalbe created this week
- Open Actionalbe created > 1 Month
- Open Actionalbe created < 1 Month
