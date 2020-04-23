require "slim"
require "sinatra"
require "sqlite3"
require "bcrypt"
# require "highline/import"
require_relative "model.rb"

enable :sessions


#Måste fixa så att sång filerna som visas inte läses från public mappen
#utan istället från databasen.
#Annars kommer låtar som tagits bort fortfarande visas
#Ett till problem med att läsa in filerna från public mappen är att jag
#måste ladda om servern varje gång en ny fil laddas upp för att kunna sedan

db = SQLite3::Database.new("db/database.db")
db.results_as_hash = true
existing_emails = db.execute("SELECT email FROM users")

files = Dir.entries("public/audio")
files = files[2..files.length-1]
comp = Dir.entries("public/audio/Compositions")
#comp = db.execute("SELECT * FROM files")["file_name"]
comp = comp[2..comp.length-1]
trans = Dir.entries("public/audio/Transcriptions")
trans = trans[2..trans.length-1]
comp_without_ext = []
trans_without_ext = []

comp.each do |compos|
    comp_without_ext << File.basename(compos, File.extname(compos))
end

trans.each do |transis|
    trans_without_ext << File.basename(transis, File.extname(transis))
end

progproj = Dir.entries("public/programmingprojects")
progproj = progproj[2..progproj.length-1]

#Displays front page before logged in
#
get("/") do
    session[:user_id] = nil
    slim(:index, locals:{files:files, comp:comp, trans:trans, progproj:progproj})
end

#Displays error message when trying to access logged in content while unlogged
#
get("/must_be_logged_in_error") do
    redirect("/sign_in")
    # slim(:must_be_logged_in_error)
end

#Displays upload page
#
get("/files/new") do
    if session[:user_id] == nil 
        redirect('/must_be_logged_in_error')
    else
        slim(:"files/new")
    end
end

#Uploads data to the database and redirects to the dashboard
#
post("/files/new") do
    unless params[:file] &&
            (tempfile = params[:file][:tempfile]) &&
            (name = params[:file][:filename])
        @error = "No file selected"
        return slim(:"dashboard")
    end

    upload_date = Time.new.inspect.split(" +")[0]

    upload_file(session[:user_id], name, upload_date)

    puts "Upload file, original name #{name.inspect}"
    fileextension = params[:file]["filename"]
    if File.extname("#{fileextension}") == ".mp3" or File.extname("#{fileextension}") == ".wav"
        folder = params[:folder]
        target = "public/audio/#{folder}/#{name}"
    else
        target = "public/img/#{name}"
        slimroute = "img/#{name}"
        upload_avatar(slimroute, session[:user_id])
    end
    File.open(target, "wb") {|f| f.write tempfile.read}
    "Upload complete"
    redirect("/dashboard")
end

#Displays error page
#
get("/error") do
    slim(:error)
end

#Displays main page while logged in.
#
get("/dashboard") do

    allinfo = user_info(session[:user_id])

    search = params[:search]
    if session[:user_id] == nil
        redirect('/must_be_logged_in_error')
    else
        slim(:"dashboard", locals: {search: search, allinfo: allinfo, files:files, comp_without_ext: comp_without_ext, trans_without_ext: trans_without_ext, progproj:progproj})
    end
end

#Displays the page for chosen composition
#
get("/files/:i") do
    song_id = params[:i]
    allinfo = user_info(session[:user_id])    
    
    allcommentinfo = comment_info()

    comments_info = {}

    allcommentinfo.each do |comment|
        if !comment["parent_id"]
            comments_info[comment["comment_id"]] = comment
            comment["replies"] = []
        else
            parent_id = comment["parent_id"]
            comments_info[parent_id]["replies"] << comment
        end
    end
    slim(:"files/show", locals: {comments_info: comments_info.values, song_id: song_id})
end

#Uploads a comment to the database
#
post("/files/:id/comment") do
    comment = params[:comment]
    parent_id = params[:parent_id]
    song_id = params[:id]
    upload_comment(comment, parent_id, song_id)
    redirect("/files/#{params[:id]}")
end

#Displays the sign in page
#
get("/users/sign_in") do
    slim(:"users/sign_in")
end

#Verifies the password and email and if correct logs in the user and redirects to either the logged in main page or error page if wrong.
#
#
post("/users/sign_in") do
    emailreg = params[:emailreg]
    session[:username] = emailreg
    passwordreg = params[:passwordreg]
    result = confirm_user(emailreg)

    if result.empty?
        redirect("/error")
    end

    password_digest_reg = result.first["password"]
    if BCrypt::Password.new(password_digest_reg) == passwordreg
        session[:user_id] = result.first["user_id"]
        redirect("/dashboard")
    else
        redirect("/error")
    end
end

#Displays the create user page
#
get("/users/new") do
    slim(:"users/new")
end

#Creates user and redirects to the logged in main page
#
post("/users/new") do
    username = params[:username]
    email = params[:email]
    session[:username] = email
    password = params[:password]
    password_digest = BCrypt::Password.create("#{password}")
    if existing_emails.include? email
        redirect("/error_email_exist") 
    else
        create_user = create_user(username, email, password_digest)
        redirect("/dashboard")
    end
end

#Displays the profile page of the one logged in
#
get("/profile") do
    profile_pic = user_info(session[:user_id])["avatar"]
    user_comments = user_comments(session[:user_id])

    user_songs = []
    user_files = user_files(session[:user_id])
    user_files.each do |i|
        if File.extname(i["file_name"]) == ".mp3" || File.extname(i["file_name"]) == ".wav"
            user_songs << i["file_name"]
        end
    end

    slim(:profile, locals: {profile_pic: profile_pic, user_comments: user_comments, user_songs: user_songs, comp_without_ext: comp_without_ext})
end

#Deletes chosen file from the database and redirects to the profile page
#
post("/files/:id/delete") do
    todo_id = params[:id]
    delete_file(todo_id)
    redirect("/profile")
end

#Edits the chosen comment and redirects to the profile
#
post("/files/:id/edit") do
    comment_id = params[:id]
    new_comment = params[:comment]
    update_file(new_comment, comment_id) 
    redirect("/profile")
end
