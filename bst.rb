require "sinatra"
require "sinatra/reloader"
require "tilt/erubis"
require "yaml"
require 'time'
require 'pry'

configure do
  enable :sessions
  set :session_secret, 'secret'
end

helpers do
  def load_yaml_data
    YAML.load_file("database.yml")
  end

  def username_data(username)
    load_yaml_data[username]
  end

  def parse_date_time_value(entry)
    date, time = entry.split(/_[a|p]m_/)
    month, day, year = date.split("_")
    hour, mins = time.split("_")
    if entry.match?("pm")
      hour = (hour.to_i + 12).to_s
    end
    Time.new(year, month, day, hour, mins).iso8601[0..-7]
  end

  def parse_glucose_value(entry)
    item = parse_entry_url(entry)
    username_data(session[:username])["data"][item][0]
  end

  def parse_carbs_value(entry)
    item = parse_entry_url(entry)
    username_data(session[:username])["data"][item][1]
  end

  def parse_insulin_value(entry)
    item = parse_entry_url(entry)
    username_data(session[:username])["data"][item][2]
  end
end

def parse_date_time(date_time)
  date, time = date_time.split("T")
  year, month, day = date.split("-")
  hour, mins = time.split(":")
  meridian = hour.to_i >= 12 ? "pm" : "am"
  hour = hour.to_i % 12 unless hour.to_i == 12
  [month.to_i, day.to_i, year.to_i, meridian, hour.to_i, mins.to_i]
end

def parse_entry_url(url)
  url.split("_").map do |time|
    if time == "am" || time == "pm"
      time
    else
      time.to_i
    end
  end
end

def valid_password?(username, password)
  load_yaml_data[username]["password"] == password
end

def signed_in?
  !!session[:username]
end

def redirect_if_not_signed_in
  if !signed_in?
    session[:message] = "You must be signed in to proceed."
    redirect "/"
  end
end

def create_new_data(current_data, data_keys, date_time, new_entry)
  new_data = {}
  data_keys.each do |key|
    if key == date_time
      new_data[key] = new_entry
    else
      new_data[key] = current_data[key]
    end
  end

  new_data
end

get "/" do
  erb :home
end

get "/users/signin" do
  erb :signin
end

post "/users/signin" do
  username = params[:username].strip
  password = params[:password]
  if username_data(username) && valid_password?(username, password)
    session[:username] = username
    session[:message] = "Signed in as #{username}."
    redirect "/"
  else
    session[:message] = "Invalid credentials."
    erb :signin
  end
end

post "/users/signout" do
  session.delete(:username)
  session[:message] = "You have been signed out."
  redirect "/"
end

get "/data/view" do
  redirect_if_not_signed_in
  erb :view
end

get "/data/delete" do
  redirect_if_not_signed_in
  erb :delete
end

post "/:entry/delete" do
  redirect_if_not_signed_in
  data = username_data(session[:username])["data"]
  item = parse_entry_url(params[:entry])
  data.delete(item)

  yaml_data = load_yaml_data
  yaml_data[session[:username]]['data'] = data
  File.open('database.yml', 'w') { |f| f.write yaml_data.to_yaml }

  session[:message] = "The chosen entry was deleted."
  redirect "/"
end

get "/data/new" do
  redirect_if_not_signed_in
  erb :new_entry
end

post "/data/new" do
  redirect_if_not_signed_in
  date_time = parse_date_time(params[:datetime])
  new_entry = [params[:glucose], params[:carbs], params[:insulin]].map(&:to_i)
  current_data = username_data(session[:username])["data"]
  data_keys = (current_data.keys + [date_time]).sort

  new_data = create_new_data(current_data, data_keys, date_time, new_entry)

  yaml_data = load_yaml_data
  yaml_data[session[:username]]['data'] = new_data
  File.open('database.yml', 'w') { |f| f.write yaml_data.to_yaml }

  session[:message] = "The new entry was created."
  redirect "/"
end

get "/users/new" do
  erb :new_user
end

post "/users/new" do
  if params[:first_password] != params[:second_password] || params[:first_password].empty?
    session[:message] = "Error: Passwords didn't match - try again!"
    erb :new_user
  elsif username_data(params[:email]) || params[:email].empty?
    session[:message] = "Error: This user already exists!"
    erb :new_user
  else
    new_data = { "password" => params[:first_password],
                  "data" => {}
                }
    yaml_data = load_yaml_data
    yaml_data[params[:email].strip] = new_data
    File.open('database.yml', 'w') { |f| f.write yaml_data.to_yaml }

    session[:message] = "Please sign in with your new account."
    redirect "/users/signin"
  end
end

get "/:entry/edit" do
  redirect_if_not_signed_in
  @entry = params[:entry]
  erb :edit_entry
end

post "/:entry/edit" do
  redirect_if_not_signed_in
  data = username_data(session[:username])["data"]
  item = parse_entry_url(params[:entry])
  data.delete(item)

  yaml_data = load_yaml_data
  yaml_data[session[:username]]['data'] = data
  File.open('database.yml', 'w') { |f| f.write yaml_data.to_yaml }

  date_time = parse_date_time(params[:datetime])
  new_entry = [params[:glucose], params[:carbs], params[:insulin]].map(&:to_i)
  current_data = username_data(session[:username])["data"]
  data_keys = (current_data.keys + [date_time]).sort

  new_data = create_new_data(current_data, data_keys, date_time, new_entry)

  yaml_data = load_yaml_data
  yaml_data[session[:username]]['data'] = new_data
  File.open('database.yml', 'w') { |f| f.write yaml_data.to_yaml }

  session[:message] = "The entry was changed."
  redirect "/"
end
