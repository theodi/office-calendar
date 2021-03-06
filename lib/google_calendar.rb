module GCal
  require 'rubygems'
  require 'httparty'
  require 'nokogiri'
  require 'google/api_client'
  
  class Resources
    
    include HTTParty

    def self.get_resources
      token = get_auth_token
  
      doc = Nokogiri::XML self.get("https://apps-apis.google.com/a/feeds/calendar/resource/2.0/#{ENV['GAPPS_DOMAIN_NAME']}/", :headers => { "Authorization" => "GoogleLogin auth=#{token}", "Content-type" => "application/atom+xml"}).response.body

      resources = []

      doc.search('entry').each do |i|
        resources << {
          :id          => i.search('.//apps:property[@name="resourceId"]').attr('value').text,
          :name        => i.search('.//apps:property[@name="resourceCommonName"]').attr('value').text,
          :email       => i.search('.//apps:property[@name="resourceEmail"]').attr('value').text,
          :description => i.search('.//apps:property[@name="resourceDescription"]').attr('value').text,
          :type        => i.search('.//apps:property[@name="resourceType"]').attr('value').text
        }
      end
    
      return resources
    end

    def self.get_auth_token
      post = {
        'accountType' => 'HOSTED_OR_GOOGLE',
        'Email' => ENV['GAPPS_USER_EMAIL'],
        'Passwd' => ENV['GAPPS_PASSWORD'],
        'service' => 'apps',
        'source' => 'odi-officecalendar-0.1'
      }
  
      response = self.post('https://www.google.com/accounts/ClientLogin', :body => post)
      
      if response.header.code.to_i == 200
        response.body.lines.each do |line|
          return line.chomp.gsub('Auth=', '') if line.chomp.index('Auth=')
        end
      end
    end
    
  end
  
  class Events
    
    include HTTParty
  
    def self.get_events(email)
      token = get_oauth_token
    
      events = []
      json = JSON.parse self.get("https://www.googleapis.com/calendar/v3/calendars/#{email}/events?timeZone=Europe%2FLondon", :headers => { "Authorization" => "OAuth #{token}"}).response.body
    
      unless json["items"].nil?
        json["items"].each do |item|
          unless item['start'].nil? || item['status'] == "cancelled" || get_response(item) == "declined"
            events << {
              :id      => item['id'],
              :title   => item['end']['dateTime'].nil? ? "All Day" : "#{parse_time(item['start'].flatten[1])} - #{parse_time(item['end'].flatten[1])}",
              :start   => DateTime.parse(item['start'].flatten[1]),
              :end     => item['end']['dateTime'].nil? ? DateTime.parse(item['end'].flatten[1]) - 1.minute : DateTime.parse(item['end'].flatten[1]),
              :allday  => item['end']['dateTime'].nil? ? true : false,    
              :created => DateTime.parse(item['created']),
              :updated => DateTime.parse(item['updated']) 
            }
          end
        end
      end
    
      return events
    end
    
    def self.get_response(event)
      unless event['attendees'].nil?
        event['attendees'].each do |item|
          if item['self'] === true
            return item['responseStatus']
          end
        end
      end
    end
  
    def self.get_event(email, id)
      token = get_oauth_token
      JSON.parse self.get("https://www.googleapis.com/calendar/v3/calendars/#{email}/events/#{id}", :headers => { "Authorization" => "OAuth #{token}"}).response.body
    end
  
    def self.update_event(email, id)
      # At the moment this only removes all attendees (so the tests pass), but can be adapted to do more stuff if needs be
      event = get_event(email, id)
      token = get_oauth_token
        
      body           = {
        :kind        => "calendar#event",
        :start       => event['start'],
        :end         => event['end'],
        :description => event['description'],
        :attendees   => [
          {
            :email => email,
            :responseStatus => "declined"
          }
        ]
      }.to_json
    
      JSON.parse self.put("https://www.googleapis.com/calendar/v3/calendars/#{email}/events/#{id}", :body => body, :headers => { "Authorization" => "OAuth #{token}", "Content-type" => "application/json"}).response.body
    end
  
    def self.create_event(description, from, to, email)
      token = get_oauth_token
    
      if from.class == DateTime
        startdate = { 
          :dateTime  => from, 
          :timeZone => "Europe/London" 
        }
        enddate = { 
          :dateTime  => to, 
          :timeZone => "Europe/London" 
        }
      elsif from.class == Date
        startdate = { 
          :date  => from, 
          :timeZone => "Europe/London" 
        }
        enddate = { 
          :date  => to, 
          :timeZone => "Europe/London" 
        }
      end
        
      body           = {
        :kind        => "calendar#event",
        :start       => startdate,
        :end         => enddate,
        :description => description,
        :attendees   => [{ :email => email }]
      }.to_json
   
      JSON.parse self.post("https://www.googleapis.com/calendar/v3/calendars/#{email}/events", :body => body, :headers => { "Authorization" => "OAuth #{token}", "Content-type" => "application/json"}).response.body
    end
  
    def self.get_oauth_token
      @@client ||= nil
      if @@client.nil? || (@@client.authorization.issued_at + @@client.authorization.expires_in < Time.now)
        path = ENV['GAPPS_PRIVATE_KEY_PATH']
    
        key = Google::APIClient::PKCS12.load_key(path, 'notasecret')      
        asserter = Google::APIClient::JWTAsserter.new(ENV['GAPPS_SERVICE_ACCOUNT_EMAIL'],
            'https://www.googleapis.com/auth/calendar http://www.google.com/calendar/feeds/', key)
        @@client = Google::APIClient.new
        @@client.authorization = asserter.authorize(ENV['GAPPS_USER_EMAIL'])
      end
      @@client.authorization.access_token
    end
  
    def self.parse_time(datetime)
      DateTime.parse(datetime).strftime('%l:%M%P').strip
    end

  end
end