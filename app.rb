require 'sinatra'
require 'pg'
require 'json'

# ----- SERVER -----
set :bind, '0.0.0.0'
set :port, (ENV['PORT'] || 4567).to_i
set :environment, (ENV['RACK_ENV'] || 'production').to_sym

DATABASE_URL = ENV['DATABASE_URL']
abort "DATABASE_URL is not set" unless DATABASE_URL

def db
  conn = PG.connect(DATABASE_URL)
  begin
    yield conn
  ensure
    conn.close
  end
end

# ----- ROOMS -----
ROOMS = {
  "lb"     => { name: "Linebacker", color: "#ef4444", emoji: "🛡️" },
  "dl"     => { name: "D-Line",     color: "#38bdf8", emoji: "⚓"  },
  "cb"     => { name: "Cornerback", color: "#facc15", emoji: "🔒" },
  "safety" => { name: "Safety",     color: "#22c55e", emoji: "🦅" }
}

# ----- FORMATIONS (grouped) -----
FORMATIONS = {
  "Spread / Modern" => [
    "Ace (2x2)", "Trips (3x1)", "Empty (5 wide)", "Quads (4x1)",
    "Bunch", "Pistol", "Shotgun"
  ],
  "Pro / Traditional" => [
    "I-Formation", "Power I", "Split Backs", "Single Back", "Twins", "Wing Twin"
  ],
  "Option / Old School" => [
    "Wishbone", "Flexbone (Double Slot)", "Wing-T", "T-Formation",
    "Single Wing", "Double Wing"
  ],
  "Gadget / Unbalanced" => [
    "Wildcat", "Emory & Henry", "Unbalanced", "Goal Line / Heavy"
  ]
}

# Gaps per room
GAPS = {
  "lb"     => ["Strong A", "Weak A", "Strong B", "Weak B", "C-Gap", "Stack", "Walked Out"],
  "dl"     => ["A-Gap", "B-Gap", "C-Gap", "D-Gap (Edge)", "0-Tech", "Nose"],
  "cb"     => ["Press", "Off (7yd)", "Bail", "Inside Leverage", "Outside Leverage"],
  "safety" => ["Deep Half", "Middle of Field", "Alley (Force)", "Robber", "Box"]
}

POSITIONS = {
  "lb"     => ["Mike", "Will", "Sam"],
  "dl"     => ["DT (1/3-Tech)", "DE (Edge)", "NT"],
  "cb"     => ["Field CB", "Boundary CB", "Nickel"],
  "safety" => ["Free Safety", "Strong Safety"]
}

# Pre-snap read questions per room (label + options)
READS = {
  "lb" => [
    { name: "guard_key", label: "Guard Key",
      options: ["Base (Fired out)", "Pulled (Across center)", "Pass Set (High Hat)"] },
    { name: "back_flow", label: "Backfield Flow",
      options: ["Fast Flow", "Split Flow", "Pass Pro"] }
  ],
  "dl" => [
    { name: "key1", label: "Primary Key",
      options: ["Base Block", "Down Block", "Double Team", "Pass Set"] },
    { name: "key2", label: "Secondary Key",
      options: ["Flow Towards / Reach", "Flow Away / Pulled", "Pass Protection"] }
  ],
  "cb" => [
    { name: "release", label: "WR Release",
      options: ["Inside Release", "Outside Release", "Vertical Release"] },
    { name: "qb_drop", label: "QB Drop",
      options: ["3-step", "5-step", "Play Action"] }
  ],
  "safety" => [
    { name: "oline", label: "O-Line Read",
      options: ["Low Hat (Run)", "High Hat (Pass)"] },
    { name: "routes", label: "Route Concept",
      options: ["Vertical / Seams", "Crossing / Digs", "Out / Flats"] }
  ]
}

# Rule engine — returns the "correct" call based on the room + reads
def compute_rule(room_key, position, read1, read2)
  case room_key
  when "lb"
    if read1.include?("Pulled") && read2.include?("Split")
      "COUNTER/TRAP — scrape over the top and spill!"
    elsif read1.include?("Pass") || read2.include?("Pass")
      "High hat — drop to hook/curl zone. Eyes on QB."
    elsif read1.include?("Base") && read2.include?("Fast")
      "Downhill — fill your gap NOW!"
    else
      "Read flow, fit your gap, play fast!"
    end
  when "dl"
    if position.to_s.include?("DE") || position.to_s.include?("Edge")
      if read1.include?("Down")     then "Tackle blocked down — crash, spill the kickout!"
      elsif read1.include?("Pass")  then "High Hat — speed rush, contain the QB!"
      else                                "Set the edge, keep outside arm free!"
      end
    else
      if read1.include?("Down") && read2.include?("Away") then "BACK BLOCK — anchor, squeeze the puller!"
      elsif read1.include?("Double")                       then "DOUBLE TEAM — drop hips, fight pressure!"
      elsif read1.include?("Pass")                         then "HIGH HAT — convert to pass rush!"
      else                                                       "Strike breastplate, control your gap!"
      end
    end
  when "cb"
    if read1.include?("Inside") && read2.include?("3-step")
      "SLANT — plant and drive on the inside hip!"
    elsif read1.include?("Vertical") && read2.include?("5-step")
      "DEEP THREAT — stay in phase, play the pocket!"
    elsif read2.include?("Play Action")
      "RUN READ — check run-force responsibility!"
    else
      "Read hips, stay sticky, own your zone."
    end
  when "safety"
    if read1.include?("Low Hat")
      "RUN — fill the alley, come to balance, make the tackle!"
    elsif read2.include?("Crossing")
      "CROSSERS — communicate, pass off, or jump it!"
    else
      "PASS — get depth, read QB's eyes, make a play!"
    end
  end
end

# ----- DB INIT -----
db do |c|
  c.exec(<<~SQL)
    CREATE TABLE IF NOT EXISTS players (
      id SERIAL PRIMARY KEY,
      name TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT NOW()
    );
  SQL
  c.exec(<<~SQL)
    CREATE TABLE IF NOT EXISTS assignments (
      id SERIAL PRIMARY KEY,
      player_id INTEGER NOT NULL REFERENCES players(id) ON DELETE CASCADE,
      room TEXT NOT NULL,
      position TEXT,
      play_numbers TEXT NOT NULL,
      formation TEXT,
      gap TEXT,
      hudl_link TEXT,
      notes TEXT,
      created_at TIMESTAMP DEFAULT NOW()
    );
  SQL
  c.exec(<<~SQL)
    CREATE TABLE IF NOT EXISTS reports (
      id SERIAL PRIMARY KEY,
      assignment_id INTEGER NOT NULL REFERENCES assignments(id) ON DELETE CASCADE,
      player_id INTEGER NOT NULL REFERENCES players(id) ON DELETE CASCADE,
      play_num TEXT NOT NULL,
      formation TEXT,
      read1 TEXT,
      read2 TEXT,
      rule TEXT,
      created_at TIMESTAMP DEFAULT NOW()
    );
  SQL
  # Safe migration if reports table existed without formation column
  c.exec("ALTER TABLE reports ADD COLUMN IF NOT EXISTS formation TEXT")
end

# ----- HELPERS -----
helpers do
  def h(t); Rack::Utils.escape_html(t.to_s); end
  def parse_plays(s); s.to_s.split(/[\s,]+/).reject(&:empty?); end
  def room_meta(k); ROOMS[k]; end
end

# ----- PWA bits -----
get '/manifest.json' do
  content_type :json
  '{"name":"Defensive Facility","short_name":"DefFac","start_url":"/","display":"standalone","orientation":"portrait","background_color":"#0f172a","theme_color":"#0f172a","icons":[{"src":"/icon.svg","sizes":"any","type":"image/svg+xml"}]}'
end

get '/icon.svg' do
  content_type 'image/svg+xml'
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><rect width="512" height="512" rx="96" fill="#0f172a"/><text x="50%" y="55%" font-size="280" text-anchor="middle" dominant-baseline="middle">🏈</text></svg>'
end

get '/health' do
  content_type :json
  '{"ok":true}'
end

# ----- HOME -----
get '/' do
  erb :home
end

# ----- PLAYER FLOW -----
get '/player' do
  @players = db { |c| c.exec("SELECT * FROM players ORDER BY name").to_a }
  erb :player_pick
end

get '/player/:id' do
  pid = params[:id].to_i
  db do |c|
    r = c.exec_params("SELECT * FROM players WHERE id=$1", [pid])
    redirect '/player' if r.ntuples.zero?
    @player = r[0]
    @assignments = c.exec_params(
      "SELECT * FROM assignments WHERE player_id=$1 ORDER BY id DESC", [pid]
    ).to_a
    done = c.exec_params(
      "SELECT assignment_id, play_num FROM reports WHERE player_id=$1", [pid]
    ).to_a
    @done = done.map { |row| "#{row['assignment_id']}::#{row['play_num']}" }
  end
  erb :player_home
end

# Player taps a play tile -> open the reads form
get '/play/:assignment_id/:play_num' do
  aid = params[:assignment_id].to_i
  db do |c|
    a = c.exec_params("SELECT * FROM assignments WHERE id=$1", [aid])
    halt 404, "Assignment not found" if a.ntuples.zero?
    @assignment = a[0]
    @player_id  = @assignment["player_id"].to_i
    @play_num   = params[:play_num]
    # If already submitted, just bounce back
    existing = c.exec_params(
      "SELECT 1 FROM reports WHERE assignment_id=$1 AND play_num=$2",
      [aid, @play_num]
    )
    if existing.ntuples > 0
      redirect "/player/#{@player_id}"
    end
  end
  @room_key = @assignment["room"]
  @reads = READS[@room_key]
  erb :reads_form
end

post '/play/submit' do
  aid     = params[:assignment_id].to_i
  pid     = params[:player_id].to_i
  play    = params[:play_num].to_s
  formation = params[:formation].to_s
  read1   = params[:read1].to_s
  read2   = params[:read2].to_s

  rule = nil
  db do |c|
    a = c.exec_params("SELECT * FROM assignments WHERE id=$1", [aid])
    halt 400, "Bad assignment" if a.ntuples.zero?
    asg = a[0]
    rule = compute_rule(asg["room"], asg["position"], read1, read2)
    c.exec_params(
      "INSERT INTO reports (assignment_id, player_id, play_num, formation, read1, read2, rule) VALUES ($1,$2,$3,$4,$5,$6,$7)",
      [aid, pid, play, formation, read1, read2, rule]
    )
  end
  redirect "/player/#{pid}"
end

# ----- COACH FLOW -----
get '/coach' do
  erb :coach_home
end

get '/roster' do
  @players = db { |c| c.exec("SELECT * FROM players ORDER BY name").to_a }
  erb :roster
end

post '/roster/add' do
  name = params[:name].to_s.strip
  db { |c| c.exec_params("INSERT INTO players (name) VALUES ($1)", [name]) } unless name.empty?
  redirect '/roster'
end

post '/roster/delete' do
  db { |c| c.exec_params("DELETE FROM players WHERE id=$1", [params[:id].to_i]) }
  redirect '/roster'
end

get '/assign' do
  db do |c|
    @players = c.exec("SELECT * FROM players ORDER BY name").to_a
    @assignments = c.exec(<<~SQL).to_a
      SELECT a.*, p.name AS player_name,
        (SELECT COUNT(*) FROM reports r WHERE r.assignment_id = a.id) AS done_count
      FROM assignments a
      LEFT JOIN players p ON p.id = a.player_id
      ORDER BY a.id DESC
    SQL
  end
  erb :assign
end

post '/assign/add' do
  formation = params[:formation].to_s
  formation = params[:formation_other].to_s.strip if formation == "__other__"
  db do |c|
    c.exec_params(
      "INSERT INTO assignments (player_id, room, position, play_numbers, formation, gap, hudl_link, notes) " \
      "VALUES ($1,$2,$3,$4,$5,$6,$7,$8)",
      [
        params[:player_id].to_i,
        params[:room].to_s,
        params[:position].to_s,
        params[:play_numbers].to_s.strip,
        formation,
        params[:gap].to_s,
        params[:hudl_link].to_s.strip,
        params[:notes].to_s.strip
      ]
    )
  end
  redirect '/assign'
end

post '/assign/delete' do
  db { |c| c.exec_params("DELETE FROM assignments WHERE id=$1", [params[:id].to_i]) }
  redirect '/assign'
end

# ----- REPORTS / OFFICE -----
get '/office' do
  db do |c|
    @reports = c.exec(<<~SQL).to_a
      SELECT r.*, p.name AS player_name, a.room, a.gap, a.position,
             COALESCE(NULLIF(r.formation,''), a.formation) AS display_formation
      FROM reports r
      JOIN players p ON p.id = r.player_id
      JOIN assignments a ON a.id = r.assignment_id
      ORDER BY r.id DESC
      LIMIT 200
    SQL
    @total = c.exec("SELECT COUNT(*) AS n FROM reports")[0]["n"].to_i
  end
  erb :office
end

post '/office/clear' do
  db { |c| c.exec("TRUNCATE reports RESTART IDENTITY") }
  redirect '/office'
end

__END__

@@layout
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="theme-color" content="#0f172a">
  <link rel="manifest" href="/manifest.json">
  <link rel="apple-touch-icon" href="/icon.svg">
  <title>Defensive Facility</title>
  <style>
    * { box-sizing: border-box; -webkit-tap-highlight-color: rgba(255,255,255,.1); }
    body { margin:0; background:#0f172a; color:#f8fafc;
      font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
      font-size:17px; line-height:1.4;
      padding-top:env(safe-area-inset-top); padding-bottom:env(safe-area-inset-bottom); }
    .wrap { max-width:640px; margin:0 auto; padding:16px 16px 120px; }
    h1 { font-size:24px; margin:8px 0 16px; }
    h2 { font-size:19px; }
    a { color:#60a5fa; }
    label { display:block; font-weight:600; margin:14px 0 6px; font-size:14px; color:#cbd5e1; text-transform:uppercase; letter-spacing:.5px; }
    input[type=text], input[type=number], input[type=url], select, textarea {
      width:100%; padding:14px; border-radius:10px; border:1px solid #334155;
      background:#1e293b; color:#f8fafc; font-size:17px; min-height:50px;
      -webkit-appearance:none; appearance:none; font-family:inherit;
    }
    textarea { min-height:80px; resize:vertical; }
    select { background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='12' height='8' viewBox='0 0 12 8'><path d='M1 1l5 5 5-5' stroke='%23cbd5e1' stroke-width='2' fill='none'/></svg>");
      background-repeat:no-repeat; background-position:right 16px center; padding-right:40px; }
    .row { display:flex; gap:10px; }
    .row > * { flex:1; }
    .card { background:#1e293b; padding:16px; border-radius:12px; margin-bottom:16px; }
    .btn { display:block; width:100%; padding:16px; border-radius:10px;
      font-size:17px; font-weight:700; text-align:center; text-decoration:none;
      border:none; cursor:pointer; min-height:56px; color:#fff; }
    .btn-red    { background:#ef4444; }
    .btn-blue   { background:#3b82f6; }
    .btn-amber  { background:#facc15; color:#0f172a; }
    .btn-green  { background:#22c55e; }
    .btn-cyan   { background:#38bdf8; }
    .btn-ghost  { background:#334155; }
    .btn-sm     { padding:10px 14px; min-height:40px; font-size:14px; width:auto; }
    .top { display:flex; gap:10px; align-items:center; margin-bottom:14px; }
    .top h1 { flex:1; margin:0; }
    .sticky { position:fixed; left:0; right:0; bottom:0;
      padding:12px 16px calc(12px + env(safe-area-inset-bottom));
      background:linear-gradient(to top,#0f172a 70%,rgba(15,23,42,0));
      display:flex; gap:10px; }
    .sticky > * { flex:1; }
    .muted { color:#94a3b8; font-size:14px; }
    .badge { display:inline-block; padding:3px 10px; border-radius:999px; font-size:12px; font-weight:700; }
    .stat { background:#1e293b; padding:14px; border-radius:10px; text-align:center; flex:1; min-width:90px; }
    .stat h3 { margin:0; color:#94a3b8; font-size:12px; font-weight:700; text-transform:uppercase; }
    .stat p { margin:6px 0 0; font-size:24px; font-weight:700; }
    .stats { display:flex; gap:10px; flex-wrap:wrap; margin-bottom:16px; }
    .room-link { display:flex; align-items:center; padding:18px; margin:10px 0;
      background:#1e293b; color:#fff; text-decoration:none; border-radius:12px;
      font-weight:700; font-size:17px; min-height:64px; }
    .play-grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(80px,1fr)); gap:10px; }
    .play-tile { display:flex; flex-direction:column; align-items:center; justify-content:center;
      padding:18px 8px; background:#1e293b; border:2px solid #334155; border-radius:12px;
      color:#fff; text-decoration:none; font-weight:700; min-height:74px; }
    .play-tile.done { background:#14532d; border-color:#22c55e; }
    .play-tile .num { font-size:22px; }
    .play-tile .lbl { font-size:10px; color:#94a3b8; margin-top:4px; text-transform:uppercase; letter-spacing:.5px; }
    .play-tile.done .lbl { color:#86efac; }
    .info-row { display:flex; gap:8px; flex-wrap:wrap; margin:8px 0; }
    .info-row .badge { background:#334155; color:#cbd5e1; }
    table { width:100%; border-collapse:collapse; font-size:13px; }
    th, td { padding:10px 8px; border-bottom:1px solid #334155; text-align:left; }
    thead { background:#334155; }
    hr { border:none; border-top:1px solid #334155; margin:20px 0; }
  </style>
</head>
<body><div class="wrap"><%= yield %></div></body>
</html>

@@home
<h1 style="text-align:center; color:#ef4444;">🏈 Defensive Facility</h1>
<p style="text-align:center; color:#94a3b8;">Who are you?</p>

<a href="/player" class="btn btn-green" style="margin-bottom:14px;">🎮 I'm a Player</a>
<a href="/coach"  class="btn btn-blue">🎯 I'm a Coach</a>

<hr>
<a href="https://www.hudl.com" target="_blank" rel="noopener" class="btn btn-ghost">📹 Open Hudl</a>

@@player_pick
<div class="top">
  <a href="/" class="btn btn-ghost btn-sm">&larr;</a>
  <h1>Who are you?</h1>
</div>

<% if @players.empty? %>
  <div class="card">
    <p>No players on the roster yet.</p>
    <p class="muted">Ask your coach to add you.</p>
  </div>
<% else %>
  <% @players.each do |p| %>
    <a href="/player/<%= p["id"] %>" class="room-link"><%= h p["name"] %></a>
  <% end %>
<% end %>

@@player_home
<div class="top">
  <a href="/player" class="btn btn-ghost btn-sm">&larr;</a>
  <h1><%= h @player["name"] %></h1>
</div>

<% if @assignments.empty? %>
  <div class="card" style="text-align:center;">
    <h2 style="color:#94a3b8;">No assignments yet.</h2>
    <p class="muted">Check back later.</p>
  </div>
<% else %>
  <% @assignments.each do |a| %>
    <% room = room_meta(a["room"]) %>
    <% plays = parse_plays(a["play_numbers"]) %>
    <% done_n = plays.count { |pn| @done.include?("#{a["id"]}::#{pn}") } %>
    <div class="card">
      <div class="top" style="margin-bottom:8px;">
        <span class="badge" style="background:<%= room[:color] %>; color:#0f172a;">
          <%= room[:emoji] %> <%= room[:name] %>
        </span>
        <% if a["position"].to_s != "" %>
          <span class="badge" style="background:#334155; color:#cbd5e1;"><%= h a["position"] %></span>
        <% end %>
        <strong style="margin-left:auto;"><%= done_n %>/<%= plays.length %></strong>
      </div>

      <div class="info-row">
        <% if a["gap"].to_s != "" %><span class="badge">Gap: <%= h a["gap"] %></span><% end %>
      </div>

      <% if a["notes"].to_s != "" %>
        <p class="muted" style="margin:4px 0 10px;"><%= h a["notes"] %></p>
      <% end %>

      <% if a["hudl_link"].to_s != "" %>
        <a href="<%= h a["hudl_link"] %>" target="_blank" rel="noopener" class="btn btn-ghost btn-sm" style="margin-bottom:12px; width:100%;">📹 Watch film on Hudl</a>
      <% end %>

      <div class="play-grid">
        <% plays.each do |pn| %>
          <% done = @done.include?("#{a["id"]}::#{pn}") %>
          <a href="/play/<%= a["id"] %>/<%= pn %>" class="play-tile <%= done ? 'done' : '' %>">
            <span class="num"><%= h pn %></span>
            <span class="lbl"><%= done ? '✓ Done' : 'Tap' %></span>
          </a>
        <% end %>
      </div>
    </div>
  <% end %>
<% end %>

@@reads_form
<% room = room_meta(@room_key) %>
<div class="top">
  <a href="/player/<%= @player_id %>" class="btn btn-ghost btn-sm">&larr;</a>
  <h1 style="color:<%= room[:color] %>;"><%= room[:emoji] %> Play <%= h @play_num %></h1>
</div>

<div class="card">
  <p style="margin:0 0 8px;"><strong>Your pre-snap:</strong></p>
  <div class="info-row">
    <% if @assignment["position"].to_s != "" %>
      <span class="badge" style="background:#334155; color:#cbd5e1;"><%= h @assignment["position"] %></span>
    <% end %>
    <% if @assignment["gap"].to_s != "" %>
      <span class="badge" style="background:#334155; color:#cbd5e1;">Gap: <%= h @assignment["gap"] %></span>
    <% end %>
  </div>
  <% if @assignment["hudl_link"].to_s != "" %>
    <a href="<%= h @assignment["hudl_link"] %>" target="_blank" rel="noopener" class="btn btn-ghost btn-sm" style="margin-top:10px; width:100%;">📹 Watch on Hudl</a>
  <% end %>
</div>

<form id="form" action="/play/submit" method="post" class="card">
  <input type="hidden" name="assignment_id" value="<%= @assignment["id"] %>">
  <input type="hidden" name="player_id" value="<%= @player_id %>">
  <input type="hidden" name="play_num" value="<%= h @play_num %>">

  <label>1. Offensive Formation</label>
  <select name="formation" required>
    <option value="">— pick one —</option>
    <% FORMATIONS.each do |group, opts| %>
      <optgroup label="<%= group %>">
        <% opts.each do |o| %>
          <option value="<%= h o %>"<%= " selected" if @assignment["formation"].to_s == o %>><%= h o %></option>
        <% end %>
      </optgroup>
    <% end %>
  </select>

  <% @reads.each_with_index do |r, i| %>
    <label><%= i+2 %>. <%= r[:label] %></label>
    <select name="read<%= i+1 %>" required>
      <option value="">— pick one —</option>
      <% r[:options].each do |o| %>
        <option value="<%= h o %>"><%= h o %></option>
      <% end %>
    </select>
  <% end %>
</form>

<div class="sticky">
  <button type="button" onclick="document.getElementById('form').submit()" class="btn btn-green">Lock In ✓</button>
</div>

@@coach_home
<div class="top">
  <a href="/" class="btn btn-ghost btn-sm">&larr;</a>
  <h1 style="color:#3b82f6;">🎯 Coach</h1>
</div>
<a href="/roster" class="btn btn-ghost"     style="margin-bottom:12px;">👥 Roster</a>
<a href="/assign" class="btn btn-blue"      style="margin-bottom:12px;">📝 Assign Plays</a>
<a href="/office" class="btn btn-ghost"     style="margin-bottom:12px;">📋 Reports</a>
<hr>
<a href="https://www.hudl.com" target="_blank" rel="noopener" class="btn btn-ghost">📹 Hudl</a>

@@roster
<div class="top">
  <a href="/coach" class="btn btn-ghost btn-sm">&larr;</a>
  <h1>👥 Roster</h1>
</div>

<form action="/roster/add" method="post" class="card">
  <label>Add player</label>
  <input type="text" name="name" placeholder="Player name" required>
  <button type="submit" class="btn btn-green" style="margin-top:12px;">Add Player</button>
</form>

<% if @players.empty? %>
  <p class="muted" style="text-align:center;">No players yet.</p>
<% else %>
  <% @players.each do |p| %>
    <div class="card" style="display:flex; align-items:center; gap:10px; padding:12px 16px; margin-bottom:8px;">
      <strong style="flex:1;"><%= h p["name"] %></strong>
      <form action="/roster/delete" method="post" onsubmit="return confirm('Remove <%= h p["name"] %>?');">
        <input type="hidden" name="id" value="<%= p["id"] %>">
        <button type="submit" class="btn btn-ghost btn-sm">🗑️</button>
      </form>
    </div>
  <% end %>
<% end %>

@@assign
<div class="top">
  <a href="/coach" class="btn btn-ghost btn-sm">&larr;</a>
  <h1>📝 Assignments</h1>
</div>

<% if @players.empty? %>
  <div class="card">
    <p>You need players on the roster first.</p>
    <a href="/roster" class="btn btn-blue" style="margin-top:10px;">Go to Roster →</a>
  </div>
<% else %>
<form action="/assign/add" method="post" class="card">
  <h2 style="margin-top:0;">New Assignment</h2>

  <label>Player</label>
  <select name="player_id" required>
    <option value="">— pick a player —</option>
    <% @players.each do |p| %>
      <option value="<%= p["id"] %>"><%= h p["name"] %></option>
    <% end %>
  </select>

  <label>Room</label>
  <select name="room" id="room-select" required onchange="updateRoom()">
    <option value="">— pick a room —</option>
    <% ROOMS.each do |k,v| %>
      <option value="<%= k %>"><%= v[:emoji] %> <%= v[:name] %></option>
    <% end %>
  </select>

  <label>Position</label>
  <select name="position" id="pos-select">
    <option value="">— pick (optional) —</option>
  </select>

  <label>Play numbers <span class="muted">(comma or space separated)</span></label>
  <input type="text" name="play_numbers" placeholder="e.g. 12, 15, 23, 41" required>

  <label>Suggested Formation <span class="muted">(optional — player will identify this themselves)</span></label>
  <select name="formation" id="fmt-select" onchange="document.getElementById('fmt-other').style.display = (this.value === '__other__') ? 'block' : 'none';">
    <option value="">— leave blank (recommended) —</option>
    <% FORMATIONS.each do |group, opts| %>
      <optgroup label="<%= group %>">
        <% opts.each do |o| %>
          <option value="<%= h o %>"><%= h o %></option>
        <% end %>
      </optgroup>
    <% end %>
    <option value="__other__">Other (type your own)…</option>
  </select>
  <input type="text" id="fmt-other" name="formation_other" placeholder="Type formation name" style="display:none; margin-top:8px;">

  <label>Pre-Snap Gap / Alignment</label>
  <select name="gap" id="gap-select">
    <option value="">— pick (optional) —</option>
  </select>

  <label>Hudl link <span class="muted">(optional)</span></label>
  <input type="url" name="hudl_link" placeholder="https://www.hudl.com/video/...">

  <label>Notes for the player <span class="muted">(optional)</span></label>
  <textarea name="notes" placeholder="e.g. Focus on the 3rd downs"></textarea>

  <button type="submit" class="btn btn-blue" style="margin-top:16px;">Create Assignment</button>
</form>

<script>
  const POSITIONS = <%= POSITIONS.to_json %>;
  const GAPS = <%= GAPS.to_json %>;
  function fillSelect(el, items) {
    el.innerHTML = '<option value="">— pick (optional) —</option>';
    items.forEach(function(item){
      var opt = document.createElement('option');
      opt.value = item; opt.textContent = item;
      el.appendChild(opt);
    });
  }
  function updateRoom() {
    var room = document.getElementById('room-select').value;
    fillSelect(document.getElementById('pos-select'), POSITIONS[room] || []);
    fillSelect(document.getElementById('gap-select'), GAPS[room] || []);
  }
</script>
<% end %>

<h2>Active Assignments</h2>
<% if @assignments.empty? %>
  <p class="muted">None yet.</p>
<% else %>
  <% @assignments.each do |a| %>
    <% room = room_meta(a["room"]) %>
    <% plays = parse_plays(a["play_numbers"]) %>
    <div class="card">
      <div class="top" style="margin-bottom:6px;">
        <span class="badge" style="background:<%= room[:color] %>; color:#0f172a;">
          <%= room[:emoji] %> <%= room[:name] %>
        </span>
        <strong><%= h a["player_name"] %></strong>
        <span style="margin-left:auto;" class="muted"><%= a["done_count"] %>/<%= plays.length %></span>
        <form action="/assign/delete" method="post" onsubmit="return confirm('Delete this assignment?');">
          <input type="hidden" name="id" value="<%= a["id"] %>">
          <button type="submit" class="btn btn-ghost btn-sm">🗑️</button>
        </form>
      </div>
      <div class="info-row">
        <% if a["position"].to_s != "" %><span class="badge">@<%= h a["position"] %></span><% end %>
        <% if a["formation"].to_s != "" %><span class="badge">vs <%= h a["formation"] %></span><% end %>
        <% if a["gap"].to_s != "" %><span class="badge">Gap: <%= h a["gap"] %></span><% end %>
      </div>
      <p style="margin:6px 0;"><strong>Plays:</strong> <%= h a["play_numbers"] %></p>
      <% if a["notes"].to_s != "" %>
        <p class="muted" style="margin:4px 0;"><%= h a["notes"] %></p>
      <% end %>
      <% if a["hudl_link"].to_s != "" %>
        <a href="<%= h a["hudl_link"] %>" target="_blank" rel="noopener" style="font-size:14px;">📹 Film link</a>
      <% end %>
    </div>
  <% end %>
<% end %>

@@office
<div class="top">
  <a href="/coach" class="btn btn-ghost btn-sm">&larr;</a>
  <h1 style="color:#3b82f6;">📋 Reports</h1>
</div>

<div class="stats">
  <div class="stat"><h3>Total Reps</h3><p><%= @total %></p></div>
</div>

<% if @reports.empty? %>
  <div class="card" style="text-align:center;">
    <h2 style="color:#94a3b8;">Nothing yet.</h2>
    <p class="muted">Players will show up here once they log reps.</p>
  </div>
<% else %>
  <div class="card">
    <div class="top" style="margin-bottom:12px;">
      <h2 style="margin:0;">Recent Reps</h2>
      <form action="/office/clear" method="post" onsubmit="return confirm('Delete ALL reports? This cannot be undone.');" style="margin-left:auto;">
        <button type="submit" class="btn btn-red btn-sm">🗑️ Clear</button>
      </form>
    </div>
    <div style="overflow-x:auto;">
      <table>
        <thead>
          <tr><th>Player</th><th>Play</th><th>Room</th><th>Vs</th><th>Reads</th><th>Rule</th></tr>
        </thead>
        <tbody>
          <% @reports.each do |r| %>
            <% room = room_meta(r["room"]) %>
            <tr>
              <td><%= h r["player_name"] %></td>
              <td><strong><%= h r["play_num"] %></strong></td>
              <td style="color:<%= room[:color] %>;"><%= room[:emoji] %></td>
              <td style="color:#facc15;"><%= h r["display_formation"] %></td>
              <td><%= h r["read1"] %> / <%= h r["read2"] %></td>
              <td style="color:#fca5a5;"><%= h r["rule"] %></td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  </div>
<% end %>
