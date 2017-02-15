# logstash-output-threshold-alert

require 'date'
require 'time'

create_date  = "2012-6-3T09:10:10.000Z"
comment_date = "2013-7-4T10:43:35.000Z"

create_obj  = Time.parse(create_date)
comment_obj = Time.parse(comment_date)

puts create_obj
puts comment_obj

ttt_seconds = comment_obj-create_obj
ttt_minutes = ttt_seconds/60
ttt_hours   = ttt_minutes/60

puts ttt_seconds.round
puts ttt_minutes.round
puts ttt_hours.round

puts [ttt_seconds.to_i / 3600, ttt_seconds.to_i/ 60 % 60, ttt_seconds.to_i % 60].map { |t| t.to_s.rjust(2,'0') }.join(':')
