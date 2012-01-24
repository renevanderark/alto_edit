require "mongo"
require "digest/md5"

def mongo_connect
	return Mongo::Connection.new("kbresearch.nl", 27017).db("dpo_admin")["users"]
end

coll = mongo_connect

coll.find.each do |doc|
	puts doc.inspect
end

if false

coll.save({
	"username" => "user",
	"password" => Digest::MD5.hexdigest("gebruiker"),
	"role" => "user"
})

coll.save({
	"username" => "admin",
	"password" => Digest::MD5.hexdigest("administrator"),
	"role" => "admin"
})

end
