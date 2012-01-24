require "rubygems"
require "sinatra"
require "hpricot"
require "json"
require "mongo"
require "digest/md5"
require "src/json_alto"
require "src/editor_admin"
require "src/simple_get_response"

enable :sessions
config = JSON.parse(File.open("config/config.json", "r") {|f| f.read})
set :db, nil
set :config, config
set :context_root, config["context_root"]

#set :context_root, ""
set :messages, {
	"badbook" => {"err" => "Urn van boek niet gevonden"},
	"success" => {"ok" => "Boek successvol toegevoegd"},
	"alreadyAdded" => {"err" => "Boek is al toegevoegd"},
	"statusDone" => {"ok" => "De pagina is definitief opgeslagen"},
	"addUser" => {"ok" => "Gebruiker is succesvol toegevoegd"},
	"statusPending" => {"ok" => "Pagina is afgekeurd"},
	"logout" => {"ok" => "U bent uitgelogd"},
	"skippedPage" => {"ok" => "De pagina is overgeslagen"},
	"noUser" => {"err" => "Gebruikersnaam niet opgegeven"},
	"noPass" => {"err" => "Wachtwoord niet opgegeven"},
	"userNotFound" => {"err" => "Foutieve gebruikersnaam of wachtwoord"},
	"noRights" => {"err" => "U heeft geen rechten om deze pagina te bezoeken"},
	"loginRequired" => {"err" => "U bent niet ingelogd" },
	"userExists" => {"err" => "Gebruiker bestaat al" },
	"userDropped" => {"ok" => "Gebruiker is verwijderd"},
	"pageSaved" => {"ok" => "De pagina is opgeslagen"},
	"badURI" => {"err" => "Ongeldige urn opgegeven"},
	"badUsername" => {"err" => "Gebruikersnaam (min: 4 tekens) mag alleen uit letters zonder diacrieten en cijfers bestaan"},
	"badPassword" => {"err" => "Wachtwoord moet uit minimaal 6 tekens bestaan"}
}

def mongo_connect(host = options.config["mongo"]["host"], port = options.config["mongo"]["port"])
	options.db = Mongo::Connection.new(host, port)
	return options.db.db(options.config["mongo"]["update_db"])["updates"]
end

def mongo_admin_connect(host = options.config["mongo"]["host"], port = options.config["mongo"]["port"])
	options.db = Mongo::Connection.new(host, port)
	return options.db.db(options.config["mongo"]["user_db"])["admin"]
end

def mongo_user_connect(host = options.config["mongo"]["host"], port = options.config["mongo"]["port"])
	options.db = Mongo::Connection.new(host, port)
	return options.db.db(options.config["mongo"]["admin_db"])["users"]
end

def mongo_close
	options.db.close unless options.db.nil?
end

def authorize(sessionVars)
	return false unless sessionVars[:user] && sessionVars[:hashed_password] 
	coll = mongo_user_connect
	doc = coll.find_one({"username" => sessionVars[:user], "password" => sessionVars[:hashed_password]})
	return !doc.nil?
end

def lookup(user, pass)
	coll = mongo_user_connect
	return coll.find_one({"username" => user, "password" => Digest::MD5.hexdigest(pass)})
end

def parse_message(key)
	if options.messages[key]
		return {	:msg_class => options.messages[key].keys.first, 
			:msg => options.messages[key][options.messages[key].keys.first]
		}
	else
		return {:msg_class => "", :msg => ""}
	end
end

after '/*' do
	mongo_close
end

before "/*" do
	if session[:msg]
		@messages = session[:msg].map{|msg|	parse_message(msg)}
		session[:msg] = nil
	end
end

before '/webapp/*' do
	if !authorize(session)
		session[:msg] = "loginRequired"
		redirect "#{options.context_root}/login" 
	end
end

before '/webapp/admin/*' do
	if session[:role] != "admin"
		session[:msg] = ["noRights"]
		redirect "#{options.context_root}/webapp/overview"
	end
end

post "/:urn/pageInfo" do
	@pages = EditorAdmin.new(mongo_admin_connect).page_info(params[:urn], params[:username], params[:role], params[:only_rejects])
	erb :pageinfo 
end

post "/updateUser" do
	return EditorAdmin.new(mongo_admin_connect).set_user(params[:urn], params[:username], params[:role])
end

post "/:urn/pageIsNotDone" do
	coll = mongo_admin_connect
	EditorAdmin.new(coll).set_page_status(params[:urn], "pending")
	session[:msg] = ["statusPending"]
	redirect request.referer
end

post "/:urn/rejectPage" do
	coll = mongo_admin_connect
	edadmin = EditorAdmin.new(coll)
	edadmin.skip_page(params[:urn], params[:reason])
	session[:msg] = ["skippedPage"]
	pages = edadmin.page_info(params[:urn], params[:username], session[:role])
	redirect options.context_root + "/webapp/" + pages.first["urn"] + "/edit" if pages.length > 0
end

post "/add_book" do
	session[:msg] = ([EditorAdmin.new(mongo_admin_connect).add_book(params[:urn])] rescue "badURI")
	redirect "#{options.context_root}/webapp/overview"
end

post "/login" do
	@messages ||= []
	@messages << parse_message("noUser") if params[:user] == ""
	@messages << parse_message("noPass") if params[:password] == ""
	user = lookup(params[:user], params[:password])
	@messages << parse_message("userNotFound") if user.nil?

	if @messages.length == 0
		session[:user] = user["username"]
		session[:hashed_password] = user["password"]
		session[:role] = user["role"]
		redirect "#{options.context_root}/webapp/overview"
	else
		erb :login
	end
end

post "/webapp/admin/accounts" do
	@users = mongo_user_connect.find
	@messages ||= []
	@messages << parse_message("noUser") if params[:username] == ""
	@messages << parse_message("noPass") if params[:password] == ""
	@messages << parse_message("badUsername") unless params[:username].length > 3 && params[:username] =~ /^[a-zA-Z0-9]+$/
	@messages << parse_message("badPassword") unless params[:password].length > 5
	if @messages.length == 0
		coll = mongo_user_connect
		existing = coll.find_one({"username" => params[:username]})
		if existing
			@messages << parse_message("userExists")
		else
			coll.save({
				"username" => params[:username],
				"password" => Digest::MD5.hexdigest(params[:password]),
				"role" => params[:role]
			})
			@messages << parse_message("addUser")
		end
	end
	erb :accounts
end

post "/webapp/admin/drop_user" do
	if params[:username]
		coll = mongo_user_connect
		doc = coll.find_one({"username" => params[:username]})
		 if doc
			coll.remove(doc)
			session[:msg] = ["userDropped"]
		end
	end
	redirect request.referer
end

post "/viewResize/:book_urn" do
	session[:image_container_width] = params[:image_container_width]
	session[:ocr_container_width] = params[:ocr_container_width]
	session[:view_resize] = params[:book_urn]
end

post "/updatePage/:urn/asEditor/:username" do
	JSONAlto.new(mongo_connect, params[:urn]).save(params)
	if params[:finalize] || params[:finalize_and_to_overview]
		coll = mongo_admin_connect
		EditorAdmin.new(coll).set_page_status(params[:urn], "done")
		session[:msg] = ["statusDone"]
		pages = EditorAdmin.new(coll).page_info(params[:urn], params[:username], session[:role])
		redirect options.context_root + "/webapp/" + pages.first["urn"] + "/edit" if pages.length > 0 && params[:finalize]
		redirect options.context_root + "/webapp/overview"
	else
		session[:msg] = ["pageSaved"]
		redirect request.referer
	end
end

get "/index" do 
	content_type :xml, 'charset' => 'utf-8'
	coll = mongo_connect
	off = (params[:offset] ? params[:offset].to_i : 0)
	lim = (params[:limit] ? params[:limit].to_i : 50)
	out = "<updates offset=\"#{off}\" limit=\"#{lim}\" total=\"#{coll.count}\">"
	coll.find.skip(off).limit(lim).each do |doc|
		out += "<alto latestUpdateTS=\"#{doc["updates"].last.map{|k,v| k}}\">#{doc["_id"]}</alto>"
	end
	out += "</updates>"
	return out
end

get "/webapp/overview" do
	coll = mongo_admin_connect
	fields = ["urn", "title", "pending_pages", "total_pages", "done_pages", "new_pages", "editors"]
	@books = {
		"new" => coll.find({"status" => "new"}, {:fields => fields}),
		"pending" => coll.find({"status" => "pending"}, {:fields => fields}),
		"done" => coll.find({"status" => "done"}, {:fields => fields}),
		"rejected" => EditorAdmin.new(coll).get_rejected_books 
	}
	erb :overview
end

get "/webapp/admin/accounts" do
	@users = mongo_user_connect.find
	erb :accounts
end

get "/logout" do
	session[:user] = nil
	session[:role] = nil
	session[:hashed_password] = nil
	session[:msg] = ["logout"]
	redirect "#{options.context_root}/login"
end

get "/login" do
	erb :login
end

get "/webapp/:urn/edit" do
	content_type :html, 'charset' => 'utf-8'
	redirect "#{options.context_root}/webapp/overview" unless params[:urn]
	@book_urn = params[:urn].sub(/:[^:]+$/, ":xml")
	doc = mongo_admin_connect.find_one({"urn" => @book_urn})
	@title = doc["title"]
	@curpage = params[:urn].sub(/^.+:/, "").to_i
	@total_pages = doc["pages"].length
	@pages = doc["pages"]
	cur = @pages.index(@pages.detect{|p| p["urn"] == params[:urn]})
	session[:swap_ratio] = @book_urn if params[:swap_ratio] && params[:swap_ratio] == "true"
	session[:swap_ratio] = nil if params[:swap_ratio] && params[:swap_ratio] == "false"
	@reject_message = @pages[cur]["reject_message"]
	@prevPageUrn = @pages[cur - 1]["urn"] if cur > 0
	@nextPageUrn = @pages[cur + 1]["urn"] if cur < @pages.length - 1
	@editor = @pages.detect{|p| p["urn"] == params[:urn]}["editor"]
	@status = @pages.detect{|p| p["urn"] == params[:urn]}["status"]
	erb :edit
end

get "/statusPoll" do
	content_type "text/javascript", 'charset' => 'utf-8'
	coll = mongo_admin_connect
	fields = ["urn", "pending_pages", "total_pages", "done_pages", "new_pages"]
	statuses = coll.find({}, {:fields => fields}).to_a
	return JSON statuses
end

get "/:urn/xml" do
	content_type :xml, 'charset' => 'utf-8'
	timestamp = params[:timestamp] ? params[:timestamp].to_i : Time.now.to_i
	return JSONAlto.new(mongo_connect, params[:urn]).from_xml.update_xml(timestamp)
end

get "/:urn/versions" do
	content_type "text/javascript", 'charset' => 'utf-8'
	retstr = JSONAlto.new(mongo_connect, params[:urn]).versions
	return "#{params[:callback]}(#{retstr});" if params[:callback]
	return retstr
end

get "/:urn" do
	content_type "text/javascript", 'charset' => 'utf-8'
	timestamp = params[:timestamp] ? params[:timestamp].to_i : Time.now.to_i
	alto = JSONAlto.new(mongo_connect, params[:urn]).from_xml.updated(timestamp).alto
	return "#{params[:callback]}(#{JSON alto});" if params[:callback]
	return JSON alto
end

get "/" do
	redirect "#{options.context_root}/webapp/overview"
end
