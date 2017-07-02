# encoding: utf-8

#==============================================================================
# PARSE COMMAND LINE OPTIONS
#==============================================================================

require 'optparse'

options = { :action => :run }

daemonize_help = "run daemonized in the background (default: false)"
pidfile_help   = "the pid filename"
logfile_help   = "the log filename"
include_help   = "an additional $LOAD_PATH (may be used more than once)"
debug_help     = "set $DEBUG to true"
warn_help      = "enable warnings"

op = OptionParser.new
op.banner =  "An example of how to daemonize a long running Ruby process."
op.separator ""
op.separator "Usage: server [options]"
op.separator ""

op.separator ""
op.separator "Process options:"
op.on("-d", "--daemonize",   daemonize_help) {         options[:daemonize] = true  }
op.on("-p", "--pid PIDFILE", pidfile_help)   { |value| options[:pidfile]   = value }
op.on("-l", "--log LOGFILE", logfile_help)   { |value| options[:logfile]   = value }

op.separator ""
op.separator "Ruby options:"
op.on("-I", "--include PATH", include_help) { |value| $LOAD_PATH.unshift(*value.split(":").map{|v| File.expand_path(v)}) }
op.on(      "--debug",        debug_help)   { $DEBUG = true }
op.on(      "--warn",         warn_help)    { $-w = true    }

op.separator ""
op.separator "Common options:"
op.on("-h", "--help")    { options[:action] = :help    }
op.on("-v", "--version") { options[:action] = :version }


op.separator ""
op.separator "Action options:"
op.on("stop")  { options[:action] = :stop  }
op.on("start") { options[:action] = :start }

op.separator ""
op.parse!(ARGV)

options[:action] = (ARGV.pop).to_sym
#==============================================================================
# EXECUTE script
#==============================================================================

require_relative 'testwaterengine.rb' unless options[:action] == :help

#Hardcode pidfile? 

case options[:action]
when :help    
 puts op.to_s
when :version 
 puts WaterEngine::VERSION
when :stop    
 WaterEngine.stop(options)
when :start   
 WaterEngine.run(options)
end

#==============================================================================
