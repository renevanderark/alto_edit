require "mongo"

coll = Mongo::Connection.new.db("dpo_edits_v2")["admin"]
coll.drop

coll = Mongo::Connection.new.db("dpo_edits_v2")["updates"]
coll.drop

if false
coll.find.each do |doc|
#     doc["total_pages"] = doc["pages"].length
#     doc["done_pages"] = doc["pages"].select{|p| p["status"] == "done"}.length
#     doc["pending_pages"] = doc["pages"].select{|p| p["status"] == "pending"}.length
#     doc["new_pages"] = doc["pages"].select{|p| p["status"] == "new"}.length
#			doc["status"] = "pending"
#			doc["status"] = "new" if  doc["new_pages"] == doc["total_pages"]
#			doc["status"] = "done" if doc["done_pages"] == doc["total_pages"]
#			doc["editors"] = doc["pages"].map{|p| p["editor"]}.compact.uniq
			puts doc["editors"].inspect
     coll.save(doc)
end
end
