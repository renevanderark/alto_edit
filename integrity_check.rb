require "mongo"
require "src/json_alto"

def mongo_connect(host = "localhost", port = 27017)
  conn = Mongo::Connection.new(host, port)
end

conn = mongo_connect
coll = conn.db("dpo_edits_v2")["updates"]
coll.find.each do |doc|
	begin
		JSONAlto.new(coll, doc["_id"]).from_xml.update_xml(Time.now.to_i)
		print "."
		$stdout.flush
	rescue
		puts 
		puts "Error generating alto xml from #{doc["_id"]}"
	end
end
conn.close
puts
