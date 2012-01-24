require "rubygems"
require "hpricot"
require "json"
require "src/simple_get_response"

class EditorAdmin
	attr_accessor :coll, :messages
	def initialize(mongo_collection)
		self.coll = mongo_collection
	end

	def add_book(urn)
		urn += ":mpeg21" unless urn =~ /mpeg21/
		urn += ":xml" unless urn =~ /xml/
		get = SimpleGetResponse.new("http://resolver.kb.nl/resolve?urn=#{urn}")
		if get.success?
			doc = Hpricot.XML(get.body)
			pages = (doc/'//didl:Item//didl:Item').map{|x| x.attributes["dc:identifier"]}
			if pages.length > 0
				if coll.find({"urn" => urn}).count == 0
					coll.save({
						"urn" => urn,
						"title" => (doc/'//dc:title').first.innerText,
						"pages" => pages.map{|page| {
							"urn" => page,
							"editor" => nil,
							"status" => "new"
						}}
					})
					update_stats(urn)
					return "success"
				else
					return "alreadyAdded"
				end
			else
				return "badbook"
			end
		else
			return "badbook"
		end
	end

	def set_page_status(urn, status)
  	doc = coll.find_one({"urn" => urn.sub(/:[0-9]+$/, ":xml")})
	  if doc
	    page = doc["pages"].select{|p| p["urn"] == urn}.first
  	  page["status"] = status
			page["reject_message"] = nil if status == "pending"
	    coll.save(doc)
			update_stats(urn)
	  end
	end

	def skip_page(urn, msg)
  	doc = coll.find_one({"urn" => urn.sub(/:[0-9]+$/, ":xml")})
		if doc
	    page = doc["pages"].select{|p| p["urn"] == urn}.first
			page["status"] = "done"
			page["reject_message"] = msg
			coll.save(doc)
			update_stats(urn)
		end
	end

	def get_rejected_books
		return coll.find({"has_rejections" => true})
	end

	def set_user(urn, username, role)
  	doc = coll.find_one({"urn" => urn.sub(/:[0-9]+$/, ":xml")})
		if doc && role != "admin"
			page = doc["pages"].select{|p| p["urn"] == urn}.first
			if page && page["editor"].nil?
				page["editor"] = username
				page["status"] = "pending"
				coll.save(doc)
				update_stats(urn)
				return ""
			elsif page["editor"] != username && role != "admin"
				return page["editor"]
			end
		end
	end

	def page_info(urn, username, role, only_rejects = nil)
		urn.sub!(/:[0-9]{4}$/, ":xml")
		doc = coll.find_one({"urn" => urn})
		return [] if doc.nil?
		pages = doc["pages"]
		pages = pages.select{|p| p["status"] == "new" || p["editor"] == username}.reject{|p| p["status"] == "done"} if role == "user"
		pages = pages.select{|p| !p["reject_message"].nil?} if only_rejects == "true" && role == "admin"
		pages = pages[0..9] if pages.length > 10 && role == "user"
		return pages
	end

	private

	def update_stats(urn)
		urn.sub!(/:[0-9]{4}$/, ":xml")
		doc = coll.find_one({"urn" => urn})
		if doc
			doc["total_pages"] = doc["pages"].length
			doc["done_pages"] = doc["pages"].select{|p| p["status"] == "done"}.length
			doc["pending_pages"] = doc["pages"].select{|p| p["status"] == "pending"}.length
			doc["new_pages"] = doc["pages"].select{|p| p["status"] == "new"}.length
			doc["has_rejections"] = true if doc["pages"].select{|p| !p["reject_message"].nil?}.length > 0
			doc["status"] = "pending"
			doc["status"] = "new" if  doc["new_pages"] == doc["total_pages"]
			doc["status"] = "done" if doc["done_pages"] == doc["total_pages"] && doc["has_rejections"] = false
			doc["editors"] = doc["pages"].map{|p| p["editor"]}.compact.uniq
			coll.save(doc)
		end
	end
end
