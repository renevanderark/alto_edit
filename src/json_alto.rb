require "rubygems"
require "src/simple_get_response"
require "hpricot"
require "json"

class JSONAlto
	attr_accessor :coll,:urn, :alto, :mongo_doc, :doc
	def initialize(mongo_collection, urn)
		self.coll = mongo_collection
		self.urn = urn
		self.alto = {}
		tries = 0
		while(tries < 5)
			begin
				self.mongo_doc = coll.find_one("_id" => urn)
				break
			rescue
				sleep 1
				$stderr.puts "tried #{tries} times"
				tries += 1
			end
		end
	end

	def from_xml
	  get = SimpleGetResponse.new("http://resolver.kb.nl/resolve?urn=#{urn}:alto")
		if get.success?
			self.doc = Hpricot.XML(get.body)
			self.alto = {
				:identifier => urn,
				:page_width => (doc/'//Page').first.attributes["WIDTH"].to_i,
				:page_height => (doc/'//Page').first.attributes["HEIGHT"].to_i,
				:blocks => (doc/'//TextBlock').map do |tb| 
					{
						:id => tb.attributes["ID"],
						:hpos => tb.attributes["HPOS"].to_i,
						:vpos => tb.attributes["VPOS"].to_i,
						:width => tb.attributes["WIDTH"].to_i,
						:height => tb.attributes["HEIGHT"].to_i,
						:lines => (tb/'//TextLine').map do |tl|
							{
								:id => tl.attributes["ID"],
								:hpos => tl.attributes["HPOS"].to_i,
								:vpos => tl.attributes["VPOS"].to_i,
								:width => tl.attributes["WIDTH"].to_i,
								:height => tl.attributes["HEIGHT"].to_i,
								:strings => (tl/'//String').map do |s|
									{
										:id => s.attributes["ID"],
										:hpos => s.attributes["HPOS"].to_i,
										:vpos => s.attributes["VPOS"].to_i,
										:height => s.attributes["HEIGHT"].to_i,
										:width => s.attributes["WIDTH"].to_i,
										:content => s.attributes["CONTENT"] + (s == (tl/'//String').last && (tl/'HYP').length == 1 ? "-" : ""),
										:wc => s.attributes["WC"],
										:updated => false
									}
								end
							}
						end
					}
				end
			}
		end
		return self
	end

	def versions
		return "{}" if mongo_doc.nil?
		return JSON mongo_doc
	end

	def updated(timestamp)
		return self if mongo_doc.nil?

		(mongo_doc["inserts"] || []).each do |ins|
			ins.each do |ts, inserts|
				if ts.to_i <= timestamp
					(inserts||[]).each do |key, values|
						line = line_by_id(key)
						line[:strings] << {
							:id => key.gsub(/.+:/,""),
							:hpos => values["hpos"].to_i,
							:vpos => values["vpos"].to_i,
							:height => values["height"].to_i,
							:width => values["width"].to_i,
							:content => values["content"]
						}
						line[:strings] = line[:strings].sort{|a,b| a[:hpos] <=> b[:hpos]}
					end
				end
			end
		end

		(mongo_doc["updates"] || []).each do |up|
			up.each do |ts, updates|
				if ts.to_i <= timestamp
					(updates||[]).each do |key, values|
						field = field_by_id(key)
						if field
							values.each do |k,v|
								v = v.to_i if k == "hpos" || k == "width"
								field[k.to_sym] = v
							end
							field[:updated] = true
						end
					end
				end
			end
		end
		return self
	end

	def update_xml(timestamp)
		raise "No alto for this urn" if self.doc.nil?
		retval = ""
		if self.mongo_doc
			# Zero run: insert new String nodes
			insert_alto_nodes(timestamp)
			# First run: deleted String nodes
			update_alto_xml(timestamp, :delete_string_nodes)
			# Second run: update CONTENT attribute
			update_alto_xml(timestamp, :update_content)
			#  Third run: update HPOS and WIDTH attributes
			update_alto_xml(timestamp, :update_segments)
			# Fourth run: normalize white-spaces
			correct_whitespaces
			# Fifth run: correct Hyphenation
			correct_hyphenation
		end
		return doc.output(retval)
	end

	def save(params)
		if params[:update] || params[:insert]
			self.mongo_doc ||= {"_id" => params[:urn]}
			self.mongo_doc["inserts"] ||= []
			self.mongo_doc["updates"] ||= []
			self.mongo_doc["inserts"] << {Time.now.to_i.to_s => params[:insert]} if params[:insert]
			self.mongo_doc["updates"] << {Time.now.to_i.to_s => params[:update]} if params[:update]
			self.mongo_doc["editor"] ||= params[:username]
			coll.save(self.mongo_doc)
		end
	end

	private

	def update_alto_xml(timestamp, update_method)
		mongo_doc["updates"].each do |up|
			up.each do |ts, updates|
				if ts.to_i <= timestamp
					(updates||[]).each do |key, values|
						(block_id, line_id, word_id) = key.split(":")
						block = (doc/"//TextBlock[@ID=#{block_id}]").first
						line =  (block/"/TextLine[@ID=#{line_id}]").first
						string = (line/"/String[@ID=#{word_id}]").first
						self.send(update_method, key, values, block, line, string)
					end
				end
			end
		end
	end

	def insert_alto_nodes(timestamp)
		(mongo_doc["inserts"] || []).each do |ins|
			ins.each do |ts, inserts|
				if ts.to_i <= timestamp
					(inserts||[]).sort{|a,b| a[0] <=> b[0] }.each do |key, values|
						(block_id, line_id, word_id) = key.split(":")
						block = (doc/"//TextBlock[@ID=#{block_id}]").first
						line =  (block/"/TextLine[@ID=#{line_id}]").first
						after = (line/"/String[@ID=#{values["after"].gsub(/.+:/, "")}]").first
						after.after(%(<String ID="#{key.gsub(/.+:/, "")}" WIDTH="#{values["width"]}" HEIGHT="#{values["height"]}" HPOS="#{values["hpos"]}" VPOS="#{values["vpos"]}" CONTENT="#{values["content"]}" />))
					end
				end
			end
		end
	end

	def correct_hyphenation
		textlines = (doc/"TextLine")
		(textlines/"String").remove_attr("SUBS_CONTENT")
		(textlines/"String").remove_attr("SUBS_TYPE")
		textlines.each_with_index do |textline, i|
			break if i == textlines.length - 1
			last_in_line = (textline/"String").last
			next_one = (textlines[i+1]/"String").first

			if (textline/'HYP').length > 0 || last_in_line.attributes["CONTENT"] =~ /\-\s*$/
				last_in_line.set_attribute("CONTENT", last_in_line.attributes["CONTENT"].sub(/\-\s*$/, ""))
				last_in_line.set_attribute("SUBS_CONTENT", last_in_line.attributes["CONTENT"] + next_one.attributes["CONTENT"])
				last_in_line.set_attribute("SUBS_TYPE", "HypPart1")
				next_one.set_attribute("SUBS_CONTENT", last_in_line.attributes["CONTENT"] + next_one.attributes["CONTENT"])
				next_one.set_attribute("SUBS_TYPE", "HypPart2")
				if (textline/'HYP').length == 0
					est_hyp_width = (last_in_line.attributes["WIDTH"].to_i / (last_in_line.attributes["CONTENT"].length + 1.5)).to_i
					hpos = last_in_line.attributes["WIDTH"].to_i + last_in_line.attributes["HPOS"].to_i - est_hyp_width
					vpos = last_in_line.attributes["VPOS"].to_i + (last_in_line.attributes["HEIGHT"].to_i / 2).to_i
					last_in_line.after(%(<HYP CONTENT="-" WIDTH="#{est_hyp_width}" HPOS="#{hpos}" VPOS="#{vpos}" />))
				end
			end
		end
	end

	def correct_whitespaces
		(doc/"SP").remove
		id_it = 1
		(doc/"TextLine").each do |textline|
			strings = (textline/'String')
			(0..strings.length-2).each do |i|
				hpos = strings[i].attributes["HPOS"].to_i + strings[i].attributes["WIDTH"].to_i
				width = strings[i+1].attributes["HPOS"].to_i - hpos
				width = 1 if width < 0
				vpos = ((strings[i].attributes["VPOS"].to_i + strings[i+1].attributes["VPOS"].to_i).to_f / 2.0).to_i
				id = id_it
				strings[i].after(%(<SP VPOS="#{vpos}" HPOS="#{hpos}" ID="SP#{id_it}" WIDTH="#{width}"/>))
				id_it += 1
			end
		end
	end

	def update_content(key, values, block, line, string)
		if values["content"] && string
			string.set_attribute("CONTENT", values["content"])
			string.set_attribute("WC", "1")
			string.set_attribute("CC", "0" * values["content"].length)
		end
	end

	def delete_string_nodes(key, values, block, line, string)
		if values["delete"]
			deleted_node = (line/"/String[@ID=#{string.attributes["ID"]}]")
			deleted_node.remove
		end
	end

	def update_segments(key, values, block, line, string)
		string.set_attribute("HPOS", values["hpos"]) if values["hpos"]
		string.set_attribute("WIDTH", values["width"]) if values["width"]
	end
	
	def line_by_id(key)
		(block_id, line_id, word_id) = key.split(":")
		alto[:blocks].select do |b|
			b[:id] == block_id
		end.first[:lines].select do |l|
			l[:id] == line_id
		end.first
	end

	def field_by_id(key)
		(block_id, line_id, word_id) = key.split(":")
		alto[:blocks].select do |b|
			b[:id] == block_id
		end.first[:lines].select do |l|
			l[:id] == line_id
		end.first[:strings].select do |s|
			s[:id] == word_id
		end.first
	end
end
