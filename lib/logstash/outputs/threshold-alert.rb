# encoding: utf-8
require "logstash/outputs/base"
require "logstash/namespace"

# An example output that does nothing.
class LogStash::Outputs::Threshold-Alert < LogStash::Outputs::Base
  config_name "threshold_alert"

    config :to, :validate => :string, :required => true

  # The fully-qualified email address for the From: field in the email.
  config :from, :validate => :string, :default => "logstash.alert@nowhere.com"

  # The fully qualified email address for the Reply-To: field.
  config :replyto, :validate => :string

  # The fully-qualified email address(es) to include as cc: address(es).
  #
  # This field also accepts a comma-separated string of addresses, for example:
  # `"me@host.com, you@host.com"`
  config :cc, :validate => :string

  # How Logstash should send the email, either via SMTP or by invoking sendmail.
  config :via, 			  :validate => :string,  :default => "smtp"
  config :address,  	  :validate => :string,  :default => "localhost"
  config :port, 		  :validate => :number,  :default => 25
  config :domain, 		  :validate => :string,  :default => "localhost"
  config :username, 	  :validate => :string
  config :password, 	  :validate => :string
  config :authentication, :validate => :string
  config :use_tls, 		  :validate => :boolean, :default => false
  config :debug, 		  :validate => :boolean, :default => false
  config :subject, 		  :validate => :string,  :default => ""
  config :body, 		  :validate => :string,  :default => ""
  config :htmlbody, 	  :validate => :string,  :default => ""
  config :attachments, 	  :validate => :array,   :default => []
  config :contenttype, 	  :validate => :string,  :default => "text/html; charset=UTF-8"
  
  
  public
  def register
  
	require "mail"

    options = {
      :address              => @address,
      :port                 => @port,
      :domain               => @domain,
      :user_name            => @username,
      :password             => @password,
      :authentication       => @authentication,
      :enable_starttls_auto => @use_tls,
      :debug                => @debug
    }

    if @via == "smtp"
      Mail.defaults do 
        delivery_method :smtp, options
      end
    elsif @via == 'sendmail'
      Mail.defaults do
        delivery_method :sendmail
      end
    else
      Mail.defaults do
        delivery_method :@via, options
      end
    end # @via tests
    @logger.debug("Email Output Registered!", :config => options, :via => @via)
	
  end # def register

  public
  def receive(event)
  
	#find the threshold
	## If the number of logs you've received goes below a threshold over a certain period of time
	## throw up an alert. 
	
	#Send email
	  @logger.debug? and @logger.debug("Creating mail with these settings : ", :via => @via, :options => @options, :from => @from, :to => @to, :cc => @cc, :subject => @subject, :body => @body, :content_type => @contenttype, :htmlbody => @htmlbody, :attachments => @attachments, :to => to, :to => to)
	  formatedSubject = event.sprintf(@subject)
	  formattedBody = event.sprintf(@body)
	  formattedHtmlBody = event.sprintf(@htmlbody)
	  mail = Mail.new
	  mail.from = event.sprintf(@from)
	  mail.to = event.sprintf(@to)
	  if @replyto
		mail.reply_to = event.sprintf(@replyto)
	  end
	  mail.cc = event.sprintf(@cc)
	  mail.subject = formatedSubject
	  if @htmlbody.empty?
		formattedBody.gsub!(/\\n/, "\n") # Take new line in the email
		mail.body = formattedBody
	  else
		mail.text_part = Mail::Part.new do
		  content_type "text/plain; charset=UTF-8"
		  formattedBody.gsub!(/\\n/, "\n") # Take new line in the email
		  body formattedBody
		end
		mail.html_part = Mail::Part.new do
		  content_type "text/html; charset=UTF-8"
		  body formattedHtmlBody
		end
	  end
	  @attachments.each do |fileLocation|
		mail.add_file(fileLocation)
	  end # end @attachments.each
	  @logger.debug? and @logger.debug("Sending mail with these values : ", :from => mail.from, :to => mail.to, :cc => mail.cc, :subject => mail.subject)
	  begin
		mail.deliver!
	  rescue StandardError => e
		@logger.error("Something happen while delivering an email", :exception => e)
		@logger.debug? && @logger.debug("Processed event: ", :event => event)
	  end
	  
	#Create jira ticket
  
    return "Event received"
  end # def event
end # class LogStash::Outputs::Example
