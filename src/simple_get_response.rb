require "net/http"
require "uri"

class SimpleGetResponse
  attr_accessor :response, :http, :url
  def initialize(set_url)
    self.url = URI.parse(set_url)
    self.http = Net::HTTP.new(url.host, url.port)
    self.http.read_timeout = 30
    self.http.open_timeout = 30
    get_response(5)
  end

  def get_response(tries = 1)
    (0..tries).each do |i|
      success = true
      begin
        self.response = http.start {|http|
          http.request_get(url.request_uri) rescue success = false
        }
        break if success
      rescue
        puts "Try #{i} on #{self.url.request_uri}: #{$!}"
        sleep 1
      end
    end

		if response.kind_of?(Net::HTTPRedirection)
			initialize(redirect_url)
		end
  end

  def body
    return self.response.body
  end

  def success?
    case self.response
      when Net::HTTPSuccess
        return true
      else
        return false
    end
  end

  def redirect_url
    if response['location'].nil?
      response.body.match(/<a href=\"([^>]+)\">/i)[1]
    else
      response['location']
    end
  end
end
