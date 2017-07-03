# encoding: utf-8

#==============================================================================
# PARSE COMMAND LINE OPTIONS
#==============================================================================

require 'optparse'

options = { :action => :none }

daemonize_help = "run daemonized in the background (default: false)"
pidfile_help   = "the pid filename"
logfile_help   = "the log filename"
include_help   = "an additional $LOAD_PATH (may be used more than once)"
inputfile_help = "the input filename containing maxis api and aws resources"
rulefile_help  = "the rule filename containing the water engine rules"

op = OptionParser.new
op.banner =  "How to execute Water Engine CLI."
op.separator ""
op.separator "Usage: cli [action] [options]"
op.separator ""

op.separator "Action options: <start>, <stop>, <restart>"
op.separator ""

op.separator "Example: ruby cli.rb stop -p /home/vagrant/waterpid.pid -l /home/vagrant/water.log  -d -i /home/vagrant/input.json -r /home/vagrant/rules.json"
op.separator "Example: ruby cli.rb restart -p /home/vagrant/waterpid.pid -l /home/vagrant/water.log  -d -i /home/vagrant/input.json -r /home/vagrant/rules.json"
op.separator "Example: ruby cli.rb start -p /home/vagrant/waterpid.pid -l /home/vagrant/water.log  -d -i /home/vagrant/input.json -r /home/vagrant/rules.json"
op.separator "Example: ruby cli.rb --help"

op.separator "Process options:"
op.on("-d", "--daemonize",      daemonize_help)  {         options[:daemonize] = true  }
op.on("-p", "--pid PIDFILE",     pidfile_help)   { |value| options[:pidfile]   = value }
op.on("-l", "--log LOGFILE",     logfile_help)   { |value| options[:logfile]   = value }
op.on("-i", "--input INPUTFILE", inputfile_help) { |value| options[:inputfile] = value }
op.on("-r", "--rules RULEFILE",   rulefile_help)  { |value| options[:rulefile]  = value }

op.separator ""
op.separator "Ruby options:"
op.on("-I", "--include PATH", include_help) { |value| $LOAD_PATH.unshift(*value.split(":").map{|v| File.expand_path(v)}) }

op.separator ""
op.separator "Common options:"
op.on("-h", "--help")    { options[:action] = :help    }
op.on("-v", "--version") { options[:action] = :version }

op.separator ""
op.parse!(ARGV)

actionARG = ARGV.pop
options[:action] = actionARG.to_sym unless actionARG.nil?

#==============================================================================
# EXECUTE script
#==============================================================================

require_relative 'water_engine.rb' unless options[:action] == :help

case options[:action]
  when :help
    puts op.to_s
  when :version
    puts WaterEngine::VERSION
  when :stop
    WaterEngine.stop(options)
  when :start
    puts options
    WaterEngine.start(options)
  when :restart
    WaterEngine.restart(options)
  else
    puts "Invalid parameter <#{options[:action]}>. Try again"
end

#==============================================================================
