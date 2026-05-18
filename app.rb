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

# ----- DICTIONARIES -----
ROOMS = {
  "lb"     => { name: "Linebacker", color: "#ef4444", emoji: "🛡️" },
  "dl"     => { name: "D-Line",     color: "#38bdf8", emoji: "⚓"  },
  "cb"     => { name: "Cornerback", color: "#facc15", emoji: "🔒" },
  "safety" => { name: "Safety",     color: "#22c55e", emoji: "🦅" }
}

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

READS = {
  "lb" => [
    { name: "read1", label: "Guard Key",
      options: ["Base (Fired out)", "Pulled (Across center)", "Pass Set (High Hat)"] },
    { name: "read2", label: "Backfield Flow",
      options: ["Fast Flow", "Split Flow", "Pass Pro"] }
  ],
  "dl" => [
    { name: "read1", label: "Primary Key",
      options: ["Base Block", "Down Block", "Double Team", "Pass Set"] },
    { name: "read2", label: "Secondary Key",
      options: ["Flow Towards / Reach", "Flow Away / Pulled", "Pass Protection"] }
  ],
  "cb" => [
    { name: "read1", label: "WR Release",
      options: ["Inside Release", "Outside Release", "Vertical Release"] },
    { name: "read2", label: "QB Drop",
      options: ["3-step", "5-step", "Play Action"] }
  ],
  "safety" => [
    { name: "read1", label: "O-Line Read",
      options: ["Low Hat (Run)", "High Hat (Pass)"] },
    { name: "read2", label: "Route Concept",
      options: ["Vertical / Seams", "Crossing / Digs", "Out / Flats"] }
  ]
}

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
      room TEXT,
      position TEXT,
      created_at TIMESTAMP DEFAULT NOW()
    );
  SQL
  c.exec("ALTER TABLE players ADD COLUMN IF NOT EXISTS room TEXT")
  c.exec("ALTER TABLE players ADD COLUMN IF NOT EXISTS position TEXT")

  c.exec(<<~SQL)
    CREATE TABLE IF NOT EXISTS assignments (
      id SERIAL PRIMARY KEY,
      player_id INTEGER NOT NULL REFERENCES players(id) ON DELETE CASCADE,
      room TEXT,
      position TEXT,
      play_numbers TEXT NOT NULL,
      hudl_link TEXT,
      notes TEXT,
      answer_key JSONB,
      created_at TIMESTAMP DEFAULT NOW()
    );
  SQL
  c.exec("ALTER TABLE assignments ADD COLUMN IF NOT EXISTS answer_key JSONB")

  c.exec(<<~SQL)
    CREATE TABLE IF NOT EXISTS reports (
      id SERIAL PRIMARY KEY,
      assignment_id INTEGER NOT NULL REFERENCES assignments(id) ON DELETE CASCADE,
      player_id INTEGER NOT NULL REFERENCES players(id) ON DELETE CASCADE,
      play_num TEXT NOT NULL,
      formation TEXT,
      alignment TEXT,
      read1 TEXT,
      read2 TEXT,
      rule TEXT,
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW(),
      UNIQUE (assignment_id, play_num)
    );
  SQL
  c.exec("ALTER TABLE reports ADD COLUMN IF NOT EXISTS alignment TEXT")
  c.exec("ALTER TABLE reports ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT NOW()")
  # Unique constraint: ensure only one report per (assignment, play) so resubmits overwrite
  begin
    c.exec("ALTER TABLE reports ADD CONSTRAINT reports_assignment_play_unique UNIQUE (assignment_id, play_num)")
  rescue PG::Error
    # constraint already exists
  end
end

# ----- HELPERS -----
helpers do
  def h(t); Rack::Utils.escape_html(t.to_s); end
  def parse_plays(s); s.to_s.split(/[\s,]+/).reject(&:empty?); end
  def room_meta(k); ROOMS[k]; end
  def parse_answer_key(json)
    return {} if json.nil? || json.to_s.empty?
    return json if json.is_a?(Hash)
    begin
      JSON.parse(json)
    rescue JSON::ParserError
      {}
    end
  end
end

# ----- PWA -----
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
    @reports_by_aid = {}
    c.exec_params(
      "SELECT * FROM reports WHERE player_id=$1", [pid]
    ).to_a.each do |r|
      aid = r["assignment_id"].to_i
      @reports_by_aid[aid] ||= {}
      @reports_by_aid[aid][r["play_num"]] = r
    end
  end
  erb :player_home
end

# Player taps a play tile -> open the reads form (with prefill if resubmit)
get '/play/:assignment_id/:play_num' do
  aid = params[:assignment_id].to_i
  @play_num = params[:play_num]
  db do |c|
    a = c.exec_params("SELECT * FROM assignments WHERE id=$1", [aid])
    halt 404, "Assignment not found" if a.ntuples.zero?
    @assignment = a[0]
    @player_id  = @assignment["player_id"].to_i
    @room_key   = @assignment["room"]

    # Look up player position from player record if assignment didn't have it
    if @assignment["position"].to_s == ""
      pr = c.exec_params("SELECT room, position FROM players WHERE id=$1", [@player_id])
      if pr.ntuples > 0
        @room_key ||= pr[0]["room"]
        @assignment["position"] = pr[0]["position"] if @assignment["position"].to_s == ""
      end
    end

    # Existing report? prefill it
    prev = c.exec_params(
      "SELECT * FROM reports WHERE assignment_id=$1 AND play_num=$2",
      [aid, @play_num]
    )
    @previous = prev.ntuples > 0 ? prev[0] : nil
  end
  @reads = READS[@room_key] || []
  erb :reads_form
end

post '/play/submit' do
  aid       = params[:assignment_id].to_i
  pid       = params[:player_id].to_i
  play      = params[:play_num].to_s
  formation = params[:formation].to_s
  alignment = params[:alignment].to_s
  read1     = params[:read1].to_s
  read2     = params[:read2].to_s

  db do |c|
    a = c.exec_params("SELECT * FROM assignments WHERE id=$1", [aid])
    halt 400, "Bad assignment" if a.ntuples.zero?
    asg = a[0]

    # Determine room and position (prefer assignment, fall back to player)
    room = asg["room"]
    position = asg["position"]
    if room.to_s == "" || position.to_s == ""
      pr = c.exec_params("SELECT room, position FROM players WHERE id=$1", [pid])
      if pr.ntuples > 0
        room ||= pr[0]["room"]
        position ||= pr[0]["position"]
      end
    end

    rule = compute_rule(room, position, read1, read2)

    # Upsert: overwrite existing report for this (assignment, play)
    c.exec_params(<<~SQL, [aid, pid, play, formation, alignment, read1, read2, rule])
      INSERT INTO reports (assignment_id, player_id, play_num, formation, alignment, read1, read2, rule, updated_at)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8, NOW())
      ON CONFLICT (assignment_id, play_num) DO UPDATE SET
        player_id = EXCLUDED.player_id,
        formation = EXCLUDED.formation,
        alignment = EXCLUDED.alignment,
        read1     = EXCLUDED.read1,
        read2     = EXCLUDED.read2,
        rule      = EXCLUDED.rule,
        updated_at = NOW()
    SQL
  end
  redirect "/player/#{pid}"
end

# Scorecard for a finished assignment
get '/report/:assignment_id' do
  aid = params[:assignment_id].to_i
  db do |c|
    a = c.exec_params(
      "SELECT a.*, p.name AS player_name FROM assignments a JOIN players p ON p.id = a.player_id WHERE a.id=$1",
      [aid]
    )
    halt 404, "Not found" if a.ntuples.zero?
    @assignment = a[0]
    @player_id = @assignment["player_id"].to_i
    @answer_key = parse_answer_key(@assignment["answer_key"])
    @plays = parse_plays(@assignment["play_numbers"])
    @reports = {}
    c.exec_params(
      "SELECT * FROM reports WHERE assignment_id=$1 ORDER BY play_num",
      [aid]
    ).to_a.each { |r| @reports[r["play_num"]] = r }
  end
  @room = ROOMS[@assignment["room"]] || {}
  # tally
  @score = { formation: { correct: 0, graded: 0 },
             alignment: { correct: 0, graded: 0 } }
  @plays.each do |pn|
    key = @answer_key[pn] || {}
    r = @reports[pn]
    next unless r
    if key["formation"].to_s != ""
      @score[:formation][:graded] += 1
      @score[:formation][:correct] += 1 if r["formation"].to_s == key["formation"].to_s
    end
    if key["alignment"].to_s != ""
      @score[:alignment][:graded] += 1
      @score[:alignment][:correct] += 1 if r["alignment"].to_s == key["alignment"].to_s
    end
  end
  erb :report
end

# ----- COACH -----
get '/coach' do
  erb :coach_home
end

get '/roster' do
  @players = db { |c| c.exec("SELECT * FROM players ORDER BY name").to_a }
  erb :roster
end

post '/roster/add' do
  name = params[:name].to_s.strip
  room = params[:room].to_s
  position = params[:position].to_s
  if !name.empty?
    db { |c| c.exec_params("INSERT INTO players (name, room, position) VALUES ($1,$2,$3)", [name, room, position]) }
  end
  redirect '/roster'
end

post '/roster/update' do
  id = params[:id].to_i
  room = params[:room].to_s
  position = params[:position].to_s
  db { |c| c.exec_params("UPDATE players SET room=$1, position=$2 WHERE id=$3", [room, position, id]) }
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
      SELECT a.*, p.name AS player_name, p.room AS player_room, p.position AS player_position,
        (SELECT COUNT(*) FROM reports r WHERE r.assignment_id = a.id) AS done_count
      FROM assignments a
      LEFT JOIN players p ON p.id = a.player_id
      ORDER BY a.id DESC
    SQL
  end
  erb :assign
end

post '/assign/add' do
  player_id    = params[:player_id].to_i
  play_numbers = params[:play_numbers].to_s.strip
  hudl_link    = params[:hudl_link].to_s.strip
  notes        = params[:notes].to_s.strip

  # Build answer key from per-play form fields
  answer_key = {}
  parse_plays(play_numbers).each do |pn|
    f = params["formation_#{pn}"].to_s
    a = params["alignment_#{pn}"].to_s
    answer_key[pn] = { "formation" => f, "alignment" => a } if f != "" || a != ""
  end

  db do |c|
    # Pull room/position from player
    pr = c.exec_params("SELECT room, position FROM players WHERE id=$1", [player_id])
    room = pr.ntuples > 0 ? pr[0]["room"] : nil
    position = pr.ntuples > 0 ? pr[0]["position"] : nil

    c.exec_params(<<~SQL, [player_id, room, position, play_numbers, hudl_link, notes, answer_key.to_json])
      INSERT INTO assignments (player_id, room, position, play_numbers, hudl_link, notes, answer_key)
      VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb)
    SQL
  end
  redirect '/assign'
end

post '/assign/delete' do
  db { |c| c.exec_params("DELETE FROM assignments WHERE id=$1", [params[:id].to_i]) }
  redirect '/assign'
end

# Endpoint that the new-assignment form pings to render the per-play answer-key inputs after typing play numbers
get '/assign/keys' do
  content_type :html
  plays = parse_plays(params[:plays])
  room  = params[:room].to_s
  gaps  = GAPS[room] || []
  html = ""
  plays.each do |pn|
    html << %Q{<div class="card" style="padding:12px; margin-bottom:10px;">
      <strong>Play #{h pn}</strong>
      <label style="margin-top:8px;">Correct Formation (optional)</label>
      <select name="formation_#{h pn}">
        <option value="">— no answer —</option>}
    FORMATIONS.each do |group, opts|
      html << %Q{<optgroup label="#{h group}">}
      opts.each { |o| html << %Q{<option value="#{h o}">#{h o}</option>} }
      html << "</optgroup>"
    end
    html << %Q{</select>
      <label>Correct Alignment (optional)</label>
      <select name="alignment_#{h pn}">
        <option value="">— no answer —</option>}
    gaps.each { |g| html << %Q{<option value="#{h g}">#{h g}</option>} }
    html << "</select></div>"
  end
  html
end

# ----- OFFICE -----
get '/office' do
  db do |c|
    @reports = c.exec(<<~SQL).to_a
      SELECT r.*, p.name AS player_name, a.room, a.position, a.answer_key
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
    th, td { padding:10px 8px; border-bottom:1px solid #334155; text-align:left; vertical-align:top; }
    thead { background:#334155; }
    hr { border:none; border-top:1px solid #334155; margin:20px 0; }
    .correct { color:#86efac; }
    .wrong   { color:#fca5a5; }
    .neutral { color:#cbd5e1; }
  </style>
</head>
<body><div class="wrap"><%= yield %></div></body>
</html>

@@home
<h1 style="text-align:center; color:#ef4444;">🏈 Defensive Facility</h1>
<p style="text-align:center; color:#94a3b8;">Who are you?</p>

<a href="/player" class="btn btn-green" style="margin-bottom:14px;">🎮 I'm a Player</a>
<a href="/coach"  class="btn btn-blue">🎯 I'm a Coach</a>

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
    <% room = room_meta(p["room"]) %>
    <a href="/player/<%= p["id"] %>" class="room-link">
      <span style="flex:1;"><%= h p["name"] %></span>
      <% if room %>
        <span class="badge" style="background:<%= room[:color] %>; color:#0f172a;">
          <%= room[:emoji] %> <%= h p["position"].to_s != "" ? p["position"] : room[:name] %>
        </span>
      <% end %>
    </a>
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
    <% room = room_meta(a["room"] || @player["room"]) %>
    <% plays = parse_plays(a["play_numbers"]) %>
    <% reports_here = @reports_by_aid[a["id"].to_i] || {} %>
    <% done_n = plays.count { |pn| reports_here.key?(pn) } %>
    <% complete = (done_n == plays.length) && plays.length > 0 %>
    <div class="card">
      <div class="top" style="margin-bottom:8px;">
        <% if room %>
          <span class="badge" style="background:<%= room[:color] %>; color:#0f172a;">
            <%= room[:emoji] %> <%= room[:name] %>
          </span>
        <% end %>
        <strong style="margin-left:auto;"><%= done_n %>/<%= plays.length %></strong>
      </div>

      <% if a["notes"].to_s != "" %>
        <p class="muted" style="margin:4px 0 10px;"><%= h a["notes"] %></p>
      <% end %>

      <% if a["hudl_link"].to_s != "" %>
        <a href="<%= h a["hudl_link"] %>" target="_blank" rel="noopener" class="btn btn-ghost btn-sm" style="margin-bottom:12px; width:100%;">📹 Open film library on Hudl</a>
      <% end %>

      <div class="play-grid">
        <% plays.each do |pn| %>
          <% done = reports_here.key?(pn) %>
          <a href="/play/<%= a["id"] %>/<%= pn %>" class="play-tile <%= done ? 'done' : '' %>">
            <span class="num"><%= h pn %></span>
            <span class="lbl"><%= done ? '✓ Done' : 'Tap' %></span>
          </a>
        <% end %>
      </div>

      <% if complete %>
        <a href="/report/<%= a["id"] %>" class="btn btn-blue" style="margin-top:14px;">📊 View Report</a>
      <% end %>
    </div>
  <% end %>
<% end %>

@@reads_form
<% room = room_meta(@room_key) || {} %>
<% gaps = GAPS[@room_key] || [] %>
<div class="top">
  <a href="/player/<%= @player_id %>" class="btn btn-ghost btn-sm">&larr;</a>
  <h1 style="color:<%= room[:color] %>;"><%= room[:emoji] %> Play <%= h @play_num %></h1>
</div>

<div class="card">
  <p style="margin:0 0 8px;"><strong>You:</strong>
    <span class="muted"><%= h(@assignment["position"].to_s != "" ? @assignment["position"] : room[:name]) %></span>
  </p>
  <% if @assignment["hudl_link"].to_s != "" %>
    <a href="<%= h @assignment["hudl_link"] %>" target="_blank" rel="noopener" class="btn btn-ghost btn-sm" style="margin-top:6px; width:100%;">📹 Find play <%= h @play_num %> in Hudl</a>
  <% end %>
  <% if @previous %>
    <p class="muted" style="margin-top:10px; font-size:13px;">You can change your previous answers below.</p>
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
          <option value="<%= h o %>"<%= " selected" if @previous && @previous["formation"].to_s == o %>><%= h o %></option>
        <% end %>
      </optgroup>
    <% end %>
  </select>

  <label>2. Pre-Snap Alignment / Gap</label>
  <select name="alignment" required>
    <option value="">— pick one —</option>
    <% gaps.each do |g| %>
      <option value="<%= h g %>"<%= " selected" if @previous && @previous["alignment"].to_s == g %>><%= h g %></option>
    <% end %>
  </select>

  <% @reads.each_with_index do |r, i| %>
    <% prev_val = @previous ? @previous["read#{i+1}"].to_s : "" %>
    <label><%= i+3 %>. <%= r[:label] %> <span class="muted">(post-snap)</span></label>
    <select name="read<%= i+1 %>" required>
      <option value="">— pick one —</option>
      <% r[:options].each do |o| %>
        <option value="<%= h o %>"<%= " selected" if prev_val == o %>><%= h o %></option>
      <% end %>
    </select>
  <% end %>
</form>

<div class="sticky">
  <button type="button" onclick="document.getElementById('form').submit()" class="btn btn-green"><%= @previous ? 'Save Changes ✓' : 'Lock In ✓' %></button>
</div>

@@report
<div class="top">
  <a href="/player/<%= @player_id %>" class="btn btn-ghost btn-sm">&larr;</a>
  <h1>📊 Report</h1>
</div>

<div class="card">
  <p style="margin:0;"><strong><%= h @assignment["player_name"] %></strong></p>
  <% if @room[:name] %>
    <p class="muted" style="margin:4px 0 0;"><%= @room[:emoji] %> <%= @room[:name] %></p>
  <% end %>
</div>

<% if @score[:formation][:graded] + @score[:alignment][:graded] == 0 %>
  <div class="card">
    <p class="muted">No answer key was set for this assignment — there's nothing to grade. You can still review what you wrote below.</p>
  </div>
<% else %>
  <div class="stats">
    <% if @score[:formation][:graded] > 0 %>
      <div class="stat" style="border-top:3px solid #facc15;">
        <h3>Formation</h3>
        <p><%= @score[:formation][:correct] %>/<%= @score[:formation][:graded] %></p>
      </div>
    <% end %>
    <% if @score[:alignment][:graded] > 0 %>
      <div class="stat" style="border-top:3px solid #60a5fa;">
        <h3>Alignment</h3>
        <p><%= @score[:alignment][:correct] %>/<%= @score[:alignment][:graded] %></p>
      </div>
    <% end %>
  </div>
<% end %>

<div class="card">
  <h2 style="margin-top:0;">Play-by-Play</h2>
  <div style="overflow-x:auto;">
    <table>
      <thead><tr><th>Play</th><th>Formation</th><th>Alignment</th><th>Reads → Call</th></tr></thead>
      <tbody>
        <% @plays.each do |pn| %>
          <% r = @reports[pn] %>
          <% key = @answer_key[pn] || {} %>
          <tr>
            <td><strong><%= h pn %></strong></td>
            <td>
              <% if r.nil? %>
                <span class="muted">—</span>
              <% else %>
                <% if key["formation"].to_s != "" %>
                  <% if r["formation"].to_s == key["formation"].to_s %>
                    <span class="correct">✓ <%= h r["formation"] %></span>
                  <% else %>
                    <span class="wrong">✗ <%= h r["formation"] %></span><br>
                    <span class="muted" style="font-size:12px;">was: <%= h key["formation"] %></span>
                  <% end %>
                <% else %>
                  <span class="neutral"><%= h r["formation"] %></span>
                <% end %>
              <% end %>
            </td>
            <td>
              <% if r.nil? %>
                <span class="muted">—</span>
              <% else %>
                <% if key["alignment"].to_s != "" %>
                  <% if r["alignment"].to_s == key["alignment"].to_s %>
                    <span class="correct">✓ <%= h r["alignment"] %></span>
                  <% else %>
                    <span class="wrong">✗ <%= h r["alignment"] %></span><br>
                    <span class="muted" style="font-size:12px;">was: <%= h key["alignment"] %></span>
                  <% end %>
                <% else %>
                  <span class="neutral"><%= h r["alignment"] %></span>
                <% end %>
              <% end %>
            </td>
            <td>
              <% if r.nil? %>
                <span class="muted">not done</span>
              <% else %>
                <span class="muted"><%= h r["read1"] %> / <%= h r["read2"] %></span><br>
                <span style="color:#fca5a5;"><%= h r["rule"] %></span>
              <% end %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>

<div class="sticky">
  <a href="/player/<%= @player_id %>" class="btn btn-ghost">&larr; Back to Plays</a>
</div>

@@coach_home
<div class="top">
  <a href="/" class="btn btn-ghost btn-sm">&larr;</a>
  <h1 style="color:#3b82f6;">🎯 Coach</h1>
</div>
<a href="/roster" class="btn btn-ghost"     style="margin-bottom:12px;">👥 Roster</a>
<a href="/assign" class="btn btn-blue"      style="margin-bottom:12px;">📝 Assign Plays</a>
<a href="/office" class="btn btn-ghost"     style="margin-bottom:12px;">📋 Reports</a>

@@roster
<div class="top">
  <a href="/coach" class="btn btn-ghost btn-sm">&larr;</a>
  <h1>👥 Roster</h1>
</div>

<form action="/roster/add" method="post" class="card">
  <h2 style="margin-top:0;">Add Player</h2>
  <label>Name</label>
  <input type="text" name="name" placeholder="Player name" required>
  <label>Room</label>
  <select name="room" id="add-room" required onchange="updateAddPositions()">
    <option value="">— pick a room —</option>
    <% ROOMS.each do |k,v| %><option value="<%= k %>"><%= v[:emoji] %> <%= v[:name] %></option><% end %>
  </select>
  <label>Position</label>
  <select name="position" id="add-position" required></select>
  <button type="submit" class="btn btn-green" style="margin-top:14px;">Add Player</button>
</form>

<% if @players.empty? %>
  <p class="muted" style="text-align:center;">No players yet.</p>
<% else %>
  <% @players.each do |p| %>
    <% room = room_meta(p["room"]) %>
    <div class="card">
      <div class="top" style="margin-bottom:6px;">
        <strong style="flex:1;"><%= h p["name"] %></strong>
        <% if room %>
          <span class="badge" style="background:<%= room[:color] %>; color:#0f172a;">
            <%= room[:emoji] %> <%= h p["position"].to_s != "" ? p["position"] : room[:name] %>
          </span>
        <% end %>
        <form action="/roster/delete" method="post" onsubmit="return confirm('Remove <%= h p["name"] %>?');">
          <input type="hidden" name="id" value="<%= p["id"] %>">
          <button type="submit" class="btn btn-ghost btn-sm">🗑️</button>
        </form>
      </div>
      <form action="/roster/update" method="post" style="display:flex; gap:8px; align-items:end; margin-top:8px;">
        <input type="hidden" name="id" value="<%= p["id"] %>">
        <div style="flex:1;">
          <label style="font-size:11px;">Room</label>
          <select name="room" class="row-room" data-player-id="<%= p["id"] %>" data-current-position="<%= h p["position"] %>" onchange="updateRowPositions(this)">
            <% ROOMS.each do |k,v| %>
              <option value="<%= k %>"<%= " selected" if p["room"] == k %>><%= v[:emoji] %> <%= v[:name] %></option>
            <% end %>
          </select>
        </div>
        <div style="flex:1;">
          <label style="font-size:11px;">Position</label>
          <select name="position" class="row-position" data-player-id="<%= p["id"] %>"></select>
        </div>
        <button type="submit" class="btn btn-blue btn-sm">Save</button>
      </form>
    </div>
  <% end %>
<% end %>

<script>
  const POSITIONS = <%= POSITIONS.to_json %>;
  function fillOptions(selectEl, items, selected) {
    selectEl.innerHTML = '';
    items.forEach(function(item){
      var opt = document.createElement('option');
      opt.value = item; opt.textContent = item;
      if (item === selected) opt.selected = true;
      selectEl.appendChild(opt);
    });
  }
  function updateAddPositions() {
    var room = document.getElementById('add-room').value;
    fillOptions(document.getElementById('add-position'), POSITIONS[room] || [], null);
  }
  function updateRowPositions(roomSelect) {
    var posSelect = roomSelect.closest('form').querySelector('.row-position');
    var current = roomSelect.getAttribute('data-current-position');
    fillOptions(posSelect, POSITIONS[roomSelect.value] || [], current);
  }
  // initialize each row
  document.querySelectorAll('.row-room').forEach(function(r){ updateRowPositions(r); });
</script>

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
  <select name="player_id" id="player-select" required>
    <option value="">— pick a player —</option>
    <% @players.each do |p| %>
      <% room = room_meta(p["room"]) %>
      <option value="<%= p["id"] %>" data-room="<%= h p["room"] %>"><%= h p["name"] %><%= room ? " — #{room[:name]}" : "" %></option>
    <% end %>
  </select>

  <label>Play numbers <span class="muted">(comma or space separated)</span></label>
  <input type="text" name="play_numbers" id="play-numbers" placeholder="e.g. 12, 15, 23, 41" required>

  <label>Hudl library link <span class="muted">(optional)</span></label>
  <input type="url" name="hudl_link" placeholder="https://www.hudl.com/library/...">

  <label>Notes for the player <span class="muted">(optional)</span></label>
  <textarea name="notes" placeholder="e.g. Find each play in the library and study it"></textarea>

  <hr>

  <h2 style="margin-bottom:4px;">Answer Key <span class="muted" style="font-size:14px;">(optional, per play)</span></h2>
  <p class="muted" style="margin-top:0;">Fill in what the player <em>should</em> identify. Skip a play to leave it ungraded.</p>
  <div id="keys-container">
    <p class="muted" style="text-align:center;">Pick a player and enter play numbers above to fill in answers.</p>
  </div>

  <button type="submit" class="btn btn-blue" style="margin-top:16px;">Create Assignment</button>
</form>

<script>
  let keysDebounce = null;
  function refreshKeys() {
    const room = document.querySelector('#player-select option:checked')?.dataset?.room || '';
    const plays = document.getElementById('play-numbers').value;
    if (!plays.trim() || !room) {
      document.getElementById('keys-container').innerHTML = '<p class="muted" style="text-align:center;">Pick a player and enter play numbers above to fill in answers.</p>';
      return;
    }
    fetch('/assign/keys?plays=' + encodeURIComponent(plays) + '&room=' + encodeURIComponent(room))
      .then(r => r.text())
      .then(html => { document.getElementById('keys-container').innerHTML = html; });
  }
  document.getElementById('player-select').addEventListener('change', refreshKeys);
  document.getElementById('play-numbers').addEventListener('input', function(){
    clearTimeout(keysDebounce);
    keysDebounce = setTimeout(refreshKeys, 400);
  });
</script>
<% end %>

<h2>Active Assignments</h2>
<% if @assignments.empty? %>
  <p class="muted">None yet.</p>
<% else %>
  <% @assignments.each do |a| %>
    <% room = room_meta(a["room"] || a["player_room"]) %>
    <% plays = parse_plays(a["play_numbers"]) %>
    <div class="card">
      <div class="top" style="margin-bottom:6px;">
        <% if room %>
          <span class="badge" style="background:<%= room[:color] %>; color:#0f172a;">
            <%= room[:emoji] %> <%= room[:name] %>
          </span>
        <% end %>
        <strong><%= h a["player_name"] %></strong>
        <span style="margin-left:auto;" class="muted"><%= a["done_count"] %>/<%= plays.length %></span>
        <form action="/assign/delete" method="post" onsubmit="return confirm('Delete this assignment?');">
          <input type="hidden" name="id" value="<%= a["id"] %>">
          <button type="submit" class="btn btn-ghost btn-sm">🗑️</button>
        </form>
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
          <tr><th>Player</th><th>Play</th><th>Formation</th><th>Alignment</th><th>Reads → Call</th></tr>
        </thead>
        <tbody>
          <% @reports.each do |r| %>
            <% room = room_meta(r["room"]) %>
            <% key = parse_answer_key(r["answer_key"])[r["play_num"]] || {} %>
            <tr>
              <td><%= h r["player_name"] %></td>
              <td><strong><%= h r["play_num"] %></strong></td>
              <td>
                <% if key["formation"].to_s != "" %>
                  <% if r["formation"].to_s == key["formation"].to_s %>
                    <span class="correct">✓</span> <%= h r["formation"] %>
                  <% else %>
                    <span class="wrong">✗</span> <%= h r["formation"] %>
                    <br><span class="muted" style="font-size:11px;">was: <%= h key["formation"] %></span>
                  <% end %>
                <% else %>
                  <%= h r["formation"] %>
                <% end %>
              </td>
              <td>
                <% if key["alignment"].to_s != "" %>
                  <% if r["alignment"].to_s == key["alignment"].to_s %>
                    <span class="correct">✓</span> <%= h r["alignment"] %>
                  <% else %>
                    <span class="wrong">✗</span> <%= h r["alignment"] %>
                    <br><span class="muted" style="font-size:11px;">was: <%= h key["alignment"] %></span>
                  <% end %>
                <% else %>
                  <%= h r["alignment"] %>
                <% end %>
              </td>
              <td>
                <span class="muted"><%= h r["read1"] %> / <%= h r["read2"] %></span><br>
                <span style="color:#fca5a5;"><%= h r["rule"] %></span>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  </div>
<% end %>
