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
  "dl"     => ["Defensive Tackle (1/3-Tech)", "Nose Tackle", "Defensive End (Edge)"],
  "cb"     => ["Field CB", "Boundary CB", "Nickel"],
  "safety" => ["Free Safety", "Strong Safety"]
}

MOTIONS = ["No Motion", "Motion to Strong", "Motion to Weak", "Motion to Bunch", "Shift", "Jet Motion"]

# 2026 schedule for the team dropdown on assignments
SCHEDULE = [
  { team: "New Town High School",                    date: "Aug 22" },
  { team: "Liberty High School",                     date: "Aug 28" },
  { team: "Landon School",                           date: "Sep 4"  },
  { team: "Hammond",                                 date: "Sep 10" },
  { team: "Annapolis Area Christian High School",    date: "Sep 25" },
  { team: "Severn School",                           date: "Oct 3"  },
  { team: "Archbishop Curley High School",           date: "Oct 9"  },
  { team: "Our Lady of Mount Carmel",                date: "Oct 16" },
  { team: "John Carroll High School",                date: "Oct 23" },
  { team: "St. Vincent Pallotti High School",        date: "Oct 30" },
  { team: "St. Paul's School",                       date: "Nov 6"  }
]

# Per-POSITION post-snap key options
POST_SNAP_KEYS = {
  "Mike"                           => {
    label: "Guards-to-Ball Read",
    options: [
      "Both guards fire out (downhill run)",
      "Guards pull same direction (flow)",
      "Guards pull opposite (counter/trap)",
      "Guards pass set",
      "Center reach (outside zone)"
    ]
  },
  "Will"                           => {
    label: "Near Tackle / TE Read",
    options: [
      "Down block by TE/tackle",
      "Reach block",
      "TE release / tackle pass set",
      "Pulling lineman coming at me",
      "Base run block"
    ]
  },
  "Sam"                            => {
    label: "Near Tackle / TE Read",
    options: [
      "Down block by TE/tackle",
      "Reach block",
      "TE release / tackle pass set",
      "Pulling lineman coming at me",
      "Base run block"
    ]
  },
  "Defensive Tackle (1/3-Tech)"    => {
    label: "Near Guard Read",
    options: [
      "High hat (pass set)",
      "Low hat (run block)",
      "Reach block (trying to hook me)",
      "Down block (guard blocks inside)",
      "Pull (guard leaves)"
    ]
  },
  "Nose Tackle"                    => {
    label: "Center Read",
    options: [
      "High hat (pass set)",
      "Low hat (run block)",
      "Reach block",
      "Down block",
      "Combo/Double team"
    ]
  },
  "Defensive End (Edge)"           => {
    label: "Tackle / TE Read",
    options: [
      "High hat (pass set)",
      "Low hat / down block",
      "Reach block",
      "TE arc release (possible boot)",
      "Kick-out block coming"
    ]
  },
  "Field CB"                       => {
    label: "WR Release / QB",
    options: [
      "Inside release",
      "Outside release",
      "Vertical release",
      "WR blocks down / cracks (run)",
      "QB drops back (zone)",
      "QB hands off (run support)"
    ]
  },
  "Boundary CB"                    => {
    label: "WR Release / QB",
    options: [
      "Inside release",
      "Outside release",
      "Vertical release",
      "WR blocks down / cracks (run)",
      "QB drops back (zone)",
      "QB hands off (run support)"
    ]
  },
  "Nickel"                         => {
    label: "Slot WR / OL Read",
    options: [
      "Inside release",
      "Outside release",
      "Slot blocks down (crack)",
      "Bubble screen / now route",
      "QB pass set (drop to zone)",
      "Run flow toward me"
    ]
  },
  "Free Safety"                    => {
    label: "QB / #2 / OL Read",
    options: [
      "QB drops back (read routes)",
      "Play-action (read it, stay deep)",
      "Run flow confirmed (trigger)",
      "Double move / post threat",
      "#2 vertical"
    ]
  },
  "Strong Safety"                  => {
    label: "TE / #2 Strong Read",
    options: [
      "Run flow strong (fill alley)",
      "TE vertical (carry)",
      "TE drag / flat (pass off)",
      "Play-action",
      "Crosser from backside"
    ]
  }
}

# Generic responsibility / action choices (player picks one)
RESPONSIBILITIES = [
  "Fill (gap)",
  "Spill (kickout)",
  "Box (force inside)",
  "Scrape (over the top)",
  "Drop (to zone)",
  "Rush (pass)",
  "Contain (edge)",
  "Replace (puller)",
  "Cover (man)",
  "Carry (vertical)",
  "Pass Off",
  "Force / Alley",
  "Trigger Downhill"
]

# Lookup key list for a position (falls back to room default if position unknown)
def keys_for(position, room)
  return POST_SNAP_KEYS[position] if position && POST_SNAP_KEYS[position]
  # fallback by room
  case room
  when "lb"     then POST_SNAP_KEYS["Mike"]
  when "dl"     then POST_SNAP_KEYS["Defensive Tackle (1/3-Tech)"]
  when "cb"     then POST_SNAP_KEYS["Field CB"]
  when "safety" then POST_SNAP_KEYS["Free Safety"]
  else { label: "Post-Snap Key", options: [] }
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
      team TEXT,
      created_at TIMESTAMP DEFAULT NOW()
    );
  SQL
  c.exec("ALTER TABLE assignments ADD COLUMN IF NOT EXISTS answer_key JSONB")
  c.exec("ALTER TABLE assignments ADD COLUMN IF NOT EXISTS team TEXT")

  c.exec(<<~SQL)
    CREATE TABLE IF NOT EXISTS reports (
      id SERIAL PRIMARY KEY,
      assignment_id INTEGER NOT NULL REFERENCES assignments(id) ON DELETE CASCADE,
      player_id INTEGER NOT NULL REFERENCES players(id) ON DELETE CASCADE,
      play_num TEXT NOT NULL,
      formation TEXT,
      alignment TEXT,
      motion TEXT,
      def_call TEXT,
      post_key TEXT,
      action TEXT,
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW()
    );
  SQL
  c.exec("ALTER TABLE reports ADD COLUMN IF NOT EXISTS motion TEXT")
  c.exec("ALTER TABLE reports ADD COLUMN IF NOT EXISTS def_call TEXT")
  c.exec("ALTER TABLE reports ADD COLUMN IF NOT EXISTS post_key TEXT")
  c.exec("ALTER TABLE reports ADD COLUMN IF NOT EXISTS action TEXT")
  c.exec("ALTER TABLE reports ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT NOW()")
  begin
    c.exec("ALTER TABLE reports ADD CONSTRAINT reports_assignment_play_unique UNIQUE (assignment_id, play_num)")
  rescue PG::Error
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

# ----- PLAYER -----
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
    c.exec_params("SELECT * FROM reports WHERE player_id=$1", [pid]).to_a.each do |r|
      aid = r["assignment_id"].to_i
      @reports_by_aid[aid] ||= {}
      @reports_by_aid[aid][r["play_num"]] = r
    end
  end
  erb :player_home
end

get '/play/:assignment_id/:play_num' do
  aid = params[:assignment_id].to_i
  @play_num = params[:play_num]
  db do |c|
    a = c.exec_params("SELECT * FROM assignments WHERE id=$1", [aid])
    halt 404, "Assignment not found" if a.ntuples.zero?
    @assignment = a[0]
    @player_id  = @assignment["player_id"].to_i
    @room_key   = @assignment["room"]
    @position   = @assignment["position"]

    if @room_key.to_s == "" || @position.to_s == ""
      pr = c.exec_params("SELECT room, position FROM players WHERE id=$1", [@player_id])
      if pr.ntuples > 0
        @room_key = pr[0]["room"] if @room_key.to_s == ""
        @position = pr[0]["position"] if @position.to_s == ""
      end
    end

    prev = c.exec_params("SELECT * FROM reports WHERE assignment_id=$1 AND play_num=$2", [aid, @play_num])
    @previous = prev.ntuples > 0 ? prev[0] : nil
  end
  @key_info = keys_for(@position, @room_key)
  erb :reads_form
end

post '/play/submit' do
  aid       = params[:assignment_id].to_i
  pid       = params[:player_id].to_i
  play      = params[:play_num].to_s
  formation = params[:formation].to_s
  alignment = params[:alignment].to_s
  motion    = params[:motion].to_s
  def_call  = params[:def_call].to_s
  post_key  = params[:post_key].to_s
  action    = params[:action].to_s

  db do |c|
    c.exec_params(<<~SQL, [aid, pid, play, formation, alignment, motion, def_call, post_key, action])
      INSERT INTO reports (assignment_id, player_id, play_num, formation, alignment, motion, def_call, post_key, action, updated_at)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9, NOW())
      ON CONFLICT (assignment_id, play_num) DO UPDATE SET
        player_id = EXCLUDED.player_id,
        formation = EXCLUDED.formation,
        alignment = EXCLUDED.alignment,
        motion    = EXCLUDED.motion,
        def_call  = EXCLUDED.def_call,
        post_key  = EXCLUDED.post_key,
        action    = EXCLUDED.action,
        updated_at = NOW()
    SQL
  end
  redirect "/player/#{pid}"
end

# Scorecard
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
    c.exec_params("SELECT * FROM reports WHERE assignment_id=$1 ORDER BY play_num", [aid]).to_a.each do |r|
      @reports[r["play_num"]] = r
    end
  end
  @room = ROOMS[@assignment["room"]] || {}
  @score = {
    formation: { correct: 0, graded: 0 },
    alignment: { correct: 0, graded: 0 },
    post_key:  { correct: 0, graded: 0 },
    action:    { correct: 0, graded: 0 }
  }
  @plays.each do |pn|
    key = @answer_key[pn] || {}
    r = @reports[pn]
    next unless r
    %w[formation alignment post_key].each do |field|
      next if key[field].to_s == ""
      @score[field.to_sym][:graded] += 1
      @score[field.to_sym][:correct] += 1 if r[field].to_s == key[field].to_s
    end
    if key["action"].to_s != ""
      @score[:action][:graded] += 1
      # Action grading: case-insensitive string equality (the coach picked from same dropdown)
      @score[:action][:correct] += 1 if r["action"].to_s.downcase == key["action"].to_s.downcase
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
  team         = params[:team].to_s
  team         = params[:team_other].to_s.strip if team == "__other__"

  answer_key = {}
  parse_plays(play_numbers).each do |pn|
    entry = {
      "formation" => params["formation_#{pn}"].to_s,
      "alignment" => params["alignment_#{pn}"].to_s,
      "post_key"  => params["post_key_#{pn}"].to_s,
      "action"    => params["action_#{pn}"].to_s
    }
    answer_key[pn] = entry if entry.values.any? { |v| v != "" }
  end

  db do |c|
    pr = c.exec_params("SELECT room, position FROM players WHERE id=$1", [player_id])
    room = pr.ntuples > 0 ? pr[0]["room"] : nil
    position = pr.ntuples > 0 ? pr[0]["position"] : nil

    c.exec_params(<<~SQL, [player_id, room, position, play_numbers, hudl_link, notes, answer_key.to_json, team])
      INSERT INTO assignments (player_id, room, position, play_numbers, hudl_link, notes, answer_key, team)
      VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,$8)
    SQL
  end
  redirect '/assign'
end

post '/assign/delete' do
  db { |c| c.exec_params("DELETE FROM assignments WHERE id=$1", [params[:id].to_i]) }
  redirect '/assign'
end

# Per-play answer key inputs (rendered by JS fetch)
get '/assign/keys' do
  content_type :html
  plays = parse_plays(params[:plays])
  position = params[:position].to_s
  room = params[:room].to_s
  gaps = GAPS[room] || []
  key_info = keys_for(position, room)

  html = ""
  if plays.empty?
    html << '<p class="muted" style="text-align:center;">Enter play numbers above to fill in answers.</p>'
  else
    html << '<table class="key-table"><thead><tr><th>Play</th><th>Formation</th><th>Alignment</th><th>Post-Snap Key</th><th>Action</th></tr></thead><tbody>'
    plays.each do |pn|
      html << %Q{<tr><td><strong>#{h pn}</strong></td>}

      # Formation
      html << %Q{<td><select name="formation_#{h pn}"><option value="">—</option>}
      FORMATIONS.each do |group, opts|
        html << %Q{<optgroup label="#{h group}">}
        opts.each { |o| html << %Q{<option value="#{h o}">#{h o}</option>} }
        html << "</optgroup>"
      end
      html << "</select></td>"

      # Alignment
      html << %Q{<td><select name="alignment_#{h pn}"><option value="">—</option>}
      gaps.each { |g| html << %Q{<option value="#{h g}">#{h g}</option>} }
      html << "</select></td>"

      # Post-snap key
      html << %Q{<td><select name="post_key_#{h pn}"><option value="">—</option>}
      key_info[:options].each { |o| html << %Q{<option value="#{h o}">#{h o}</option>} }
      html << "</select></td>"

      # Action
      html << %Q{<td><select name="action_#{h pn}"><option value="">—</option>}
      RESPONSIBILITIES.each { |r| html << %Q{<option value="#{h r}">#{h r}</option>} }
      html << "</select></td></tr>"
    end
    html << "</tbody></table>"
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
    .wrap-wide { max-width:1200px; }
    h1 { font-size:24px; margin:8px 0 16px; }
    h2 { font-size:19px; }
    h3 { font-size:15px; margin:18px 0 6px; color:#94a3b8; text-transform:uppercase; letter-spacing:.5px; }
    a { color:#60a5fa; }
    label { display:block; font-weight:600; margin:14px 0 6px; font-size:14px; color:#cbd5e1; text-transform:uppercase; letter-spacing:.5px; }
    input[type=text], input[type=number], input[type=url], select, textarea {
      width:100%; padding:14px; border-radius:10px; border:1px solid #334155;
      background:#1e293b; color:#f8fafc; font-size:17px; min-height:50px;
      -webkit-appearance:none; appearance:none; font-family:inherit;
    }
    textarea { min-height:80px; resize:vertical; }
    select { background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='12' height='8' viewBox='0 0 12 8'><path d='M1 1l5 5 5-5' stroke='%23cbd5e1' stroke-width='2' fill='none'/></svg>");
      background-repeat:no-repeat; background-position:right 12px center; padding-right:36px; }
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
    .top { display:flex; gap:10px; align-items:center; margin-bottom:14px; padding-right:54px; }
    .top h1 { flex:1; margin:0; }
    .sticky { position:fixed; left:0; right:0; bottom:0;
      padding:12px 16px calc(12px + env(safe-area-inset-bottom));
      background:linear-gradient(to top,#0f172a 70%,rgba(15,23,42,0));
      display:flex; gap:10px; max-width:640px; margin:0 auto; }
    .sticky > * { flex:1; }
    .muted { color:#94a3b8; font-size:14px; }
    .badge { display:inline-block; padding:3px 10px; border-radius:999px; font-size:12px; font-weight:700; }
    .stat { background:#1e293b; padding:14px; border-radius:10px; text-align:center; flex:1; min-width:90px; }
    .stat h3 { margin:0; color:#94a3b8; font-size:12px; font-weight:700; text-transform:uppercase; letter-spacing:.5px; }
    .stat p { margin:6px 0 0; font-size:24px; font-weight:700; color:#f8fafc; }
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
    .correct { color:#86efac; font-weight:700; }
    .wrong   { color:#fca5a5; font-weight:700; }
    .neutral { color:#cbd5e1; }
    .section-tag { display:inline-block; padding:4px 10px; border-radius:6px; font-size:11px; font-weight:700; text-transform:uppercase; letter-spacing:.5px; margin-bottom:8px; }
    .pre-snap-tag  { background:rgba(59,130,246,.15); color:#93c5fd; }
    .post-snap-tag { background:rgba(239,68,68,.15); color:#fca5a5; }
    /* Answer-key compact table */
    .key-table { width:100%; font-size:13px; }
    .key-table th, .key-table td { padding:6px 4px; border-bottom:1px solid #334155; vertical-align:top; }
    .key-table select { padding:8px; font-size:14px; min-height:38px; }
    /* Desktop layout for coach pages */
    @media (min-width: 900px) {
      .wrap-wide { padding: 24px; }
      .wrap-wide .sticky { max-width:1200px; }
      .two-col { display:grid; grid-template-columns: 1fr 1.2fr; gap:20px; align-items:start; }
      .two-col > .card { margin-bottom:0; }
    }
    /* Floating home button (top-right on every page) */
    .home-fab { position:fixed; top:calc(env(safe-area-inset-top) + 12px); right:14px; z-index:50;
      background:#1e293b; border:1px solid #334155; color:#f8fafc; text-decoration:none;
      width:44px; height:44px; border-radius:22px;
      display:flex; align-items:center; justify-content:center; font-size:20px;
      box-shadow:0 4px 12px rgba(0,0,0,.3); }
    .home-fab:hover { background:#334155; }
    /* Hide on the home page itself */
    body.is-home .home-fab { display:none; }
  </style>
</head>
<body class="<%= request.path == '/' ? 'is-home' : '' %>">
  <a href="/" class="home-fab" title="Defensive Facility home">🏠</a>
  <div class="wrap <%= @wide ? 'wrap-wide' : '' %>"><%= yield %></div>
</body>
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
        <% if a["team"].to_s != "" %>
          <span class="badge" style="background:#334155; color:#cbd5e1;">vs <%= h a["team"] %></span>
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
    <span class="muted"><%= h(@position.to_s != "" ? @position : room[:name]) %></span>
  </p>
  <% if @assignment["hudl_link"].to_s != "" %>
    <a href="<%= h @assignment["hudl_link"] %>" target="_blank" rel="noopener" class="btn btn-ghost btn-sm" style="margin-top:6px; width:100%;">📹 Find play <%= h @play_num %> in Hudl</a>
  <% end %>
  <% if @previous %>
    <p class="muted" style="margin-top:10px; font-size:13px;">Editing your previous answers.</p>
  <% end %>
</div>

<form id="form" action="/play/submit" method="post">
  <input type="hidden" name="assignment_id" value="<%= @assignment["id"] %>">
  <input type="hidden" name="player_id" value="<%= @player_id %>">
  <input type="hidden" name="play_num" value="<%= h @play_num %>">

  <div class="card">
    <span class="section-tag pre-snap-tag">Pre-Snap</span>

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

    <label>2. Motion / Shift</label>
    <select name="motion">
      <option value="">— optional —</option>
      <% MOTIONS.each do |m| %>
        <option value="<%= h m %>"<%= " selected" if @previous && @previous["motion"].to_s == m %>><%= h m %></option>
      <% end %>
    </select>

    <label>3. My Alignment / Gap</label>
    <select name="alignment" required>
      <option value="">— pick one —</option>
      <% gaps.each do |g| %>
        <option value="<%= h g %>"<%= " selected" if @previous && @previous["alignment"].to_s == g %>><%= h g %></option>
      <% end %>
    </select>

    <label>4. Defensive Call <span class="muted">(what was called?)</span></label>
    <input type="text" name="def_call" placeholder="e.g. Cover 3, Tite, A-gap blitz"
      value="<%= h(@previous && @previous["def_call"]) %>">
  </div>

  <div class="card">
    <span class="section-tag post-snap-tag">Post-Snap</span>

    <label>5. <%= h @key_info[:label] %></label>
    <select name="post_key" required>
      <option value="">— pick one —</option>
      <% @key_info[:options].each do |o| %>
        <option value="<%= h o %>"<%= " selected" if @previous && @previous["post_key"].to_s == o %>><%= h o %></option>
      <% end %>
    </select>

    <label>6. My Responsibility / Action</label>
    <select name="action" required>
      <option value="">— pick one —</option>
      <% RESPONSIBILITIES.each do |r| %>
        <option value="<%= h r %>"<%= " selected" if @previous && @previous["action"].to_s == r %>><%= h r %></option>
      <% end %>
    </select>
  </div>
</form>

<div class="sticky">
  <button type="button" onclick="document.getElementById('form').submit()" class="btn btn-green"><%= @previous ? 'Save Changes ✓' : 'Lock In ✓' %></button>
</div>

@@report
<% @wide = true %>
<div class="top">
  <a href="/player/<%= @player_id %>" class="btn btn-ghost btn-sm">&larr;</a>
  <h1>📊 Report</h1>
</div>

<div class="card">
  <p style="margin:0;"><strong><%= h @assignment["player_name"] %></strong></p>
  <% if @room[:name] %>
    <p class="muted" style="margin:4px 0 0;"><%= @room[:emoji] %> <%= @room[:name] %> — <%= h @assignment["position"] %></p>
  <% end %>
  <% if @assignment["team"].to_s != "" %>
    <p class="muted" style="margin:4px 0 0;">vs <%= h @assignment["team"] %></p>
  <% end %>
</div>

<% graded_total = @score.values.sum { |s| s[:graded] } %>
<% if graded_total == 0 %>
  <div class="card">
    <p class="muted">No answer key was set for this assignment — there's nothing to grade. Review your answers below.</p>
  </div>
<% else %>
  <div class="stats">
    <% @score.each do |field, s| %>
      <% next if s[:graded] == 0 %>
      <% pct = s[:graded] > 0 ? (s[:correct] * 100.0 / s[:graded]).round : 0 %>
      <% color = pct >= 80 ? "#22c55e" : (pct >= 60 ? "#facc15" : "#ef4444") %>
      <div class="stat" style="border-top:3px solid <%= color %>;">
        <h3><%= field.to_s.gsub("_", " ") %></h3>
        <p><%= s[:correct] %>/<%= s[:graded] %></p>
      </div>
    <% end %>
  </div>
<% end %>

<div class="card">
  <h2 style="margin-top:0;">Play-by-Play</h2>
  <div style="overflow-x:auto;">
    <table>
      <thead><tr><th>Play</th><th>Formation</th><th>Alignment</th><th>Post-Snap Key</th><th>Action</th><th>Notes</th></tr></thead>
      <tbody>
        <% @plays.each do |pn| %>
          <% r = @reports[pn] %>
          <% key = @answer_key[pn] || {} %>
          <tr>
            <td><strong><%= h pn %></strong></td>
            <% %w[formation alignment post_key action].each do |field| %>
              <td>
                <% if r.nil? %>
                  <span class="muted">—</span>
                <% else %>
                  <% if key[field].to_s != "" %>
                    <% if r[field].to_s == key[field].to_s %>
                      <span class="correct">✓</span> <%= h r[field] %>
                    <% else %>
                      <span class="wrong">✗</span> <%= h r[field] %>
                      <br><span class="muted" style="font-size:11px;">was: <%= h key[field] %></span>
                    <% end %>
                  <% else %>
                    <span class="neutral"><%= h r[field] %></span>
                  <% end %>
                <% end %>
              </td>
            <% end %>
            <td class="muted" style="font-size:12px;">
              <% if r && r["motion"].to_s != "" %>Motion: <%= h r["motion"] %><br><% end %>
              <% if r && r["def_call"].to_s != "" %>Call: <%= h r["def_call"] %><% end %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>

@@coach_home
<% @wide = true %>
<div class="top">
  <a href="/" class="btn btn-ghost btn-sm">&larr;</a>
  <h1 style="color:#3b82f6;">🎯 Coach</h1>
</div>
<div style="display:grid; grid-template-columns:1fr; gap:12px;">
  <a href="/roster" class="btn btn-ghost">👥 Roster</a>
  <a href="/assign" class="btn btn-blue">📝 Assign Plays</a>
  <a href="/office" class="btn btn-ghost">📋 Reports</a>
</div>

@@roster
<% @wide = true %>
<div class="top">
  <a href="/coach" class="btn btn-ghost btn-sm">&larr;</a>
  <h1>👥 Roster</h1>
</div>

<form action="/roster/add" method="post" class="card">
  <h2 style="margin-top:0;">Add Player</h2>
  <div class="row">
    <div>
      <label>Name</label>
      <input type="text" name="name" placeholder="Player name" required>
    </div>
    <div>
      <label>Room</label>
      <select name="room" id="add-room" required onchange="updateAddPositions()">
        <option value="">— pick —</option>
        <% ROOMS.each do |k,v| %><option value="<%= k %>"><%= v[:emoji] %> <%= v[:name] %></option><% end %>
      </select>
    </div>
    <div>
      <label>Position</label>
      <select name="position" id="add-position" required></select>
    </div>
  </div>
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
          <select name="room" class="row-room" data-current-position="<%= h p["position"] %>" onchange="updateRowPositions(this)">
            <% ROOMS.each do |k,v| %>
              <option value="<%= k %>"<%= " selected" if p["room"] == k %>><%= v[:emoji] %> <%= v[:name] %></option>
            <% end %>
          </select>
        </div>
        <div style="flex:1;">
          <label style="font-size:11px;">Position</label>
          <select name="position" class="row-position"></select>
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
  document.querySelectorAll('.row-room').forEach(function(r){ updateRowPositions(r); });
</script>

@@assign
<% @wide = true %>
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
<form action="/assign/add" method="post">
  <div class="two-col">
    <div class="card">
      <h2 style="margin-top:0;">New Assignment</h2>

      <label>Player</label>
      <select name="player_id" id="player-select" required onchange="refreshKeys()">
        <option value="">— pick a player —</option>
        <% @players.each do |p| %>
          <% room = room_meta(p["room"]) %>
          <option value="<%= p["id"] %>" data-room="<%= h p["room"] %>" data-position="<%= h p["position"] %>"><%= h p["name"] %><%= room ? " — #{p["position"]}" : "" %></option>
        <% end %>
      </select>

      <label>Team / Opponent</label>
      <select name="team" id="team-select" onchange="document.getElementById('team-other-wrap').style.display = (this.value === '__other__') ? 'block' : 'none';">
        <option value="">— pick an opponent —</option>
        <% SCHEDULE.each do |g| %>
          <option value="<%= h g[:team] %>"><%= h g[:team] %> (<%= h g[:date] %>)</option>
        <% end %>
        <option value="__other__">Other (type your own)…</option>
      </select>
      <div id="team-other-wrap" style="display:none; margin-top:8px;">
        <input type="text" name="team_other" placeholder="Team name">
      </div>

      <label>Play numbers <span class="muted">(comma or space separated)</span></label>
      <input type="text" name="play_numbers" id="play-numbers" placeholder="e.g. 12, 15, 23, 41" required>

      <label>Hudl library link <span class="muted">(optional)</span></label>
      <input type="url" name="hudl_link" placeholder="https://www.hudl.com/library/...">

      <label>Notes for the player <span class="muted">(optional)</span></label>
      <textarea name="notes" placeholder="e.g. Find each play in the library and study it"></textarea>

      <button type="submit" class="btn btn-blue" style="margin-top:16px;">Create Assignment</button>
    </div>

    <div class="card">
      <h2 style="margin-top:0;">Answer Key <span class="muted" style="font-size:14px;">(optional, per play)</span></h2>
      <p class="muted" style="margin-top:0;">Fill in what the player <em>should</em> identify and do. Skip any field to leave it ungraded.</p>
      <div id="keys-container">
        <p class="muted" style="text-align:center;">Pick a player and enter play numbers to fill in answers.</p>
      </div>
    </div>
  </div>
</form>

<script>
  let keysDebounce = null;
  function refreshKeys() {
    const sel = document.querySelector('#player-select option:checked');
    const room = sel?.dataset?.room || '';
    const position = sel?.dataset?.position || '';
    const plays = document.getElementById('play-numbers').value;
    if (!plays.trim() || !room) {
      document.getElementById('keys-container').innerHTML = '<p class="muted" style="text-align:center;">Pick a player and enter play numbers to fill in answers.</p>';
      return;
    }
    const url = '/assign/keys?plays=' + encodeURIComponent(plays)
              + '&room=' + encodeURIComponent(room)
              + '&position=' + encodeURIComponent(position);
    fetch(url).then(r => r.text()).then(html => {
      document.getElementById('keys-container').innerHTML = html;
    });
  }
  document.getElementById('play-numbers').addEventListener('input', function(){
    clearTimeout(keysDebounce);
    keysDebounce = setTimeout(refreshKeys, 400);
  });
</script>
<% end %>

<h2 style="margin-top:30px;">Active Assignments</h2>
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
      <% if a["team"].to_s != "" %>
        <p style="margin:6px 0;"><strong>Vs:</strong> <%= h a["team"] %></p>
      <% end %>
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
<% @wide = true %>
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
          <tr><th>Player</th><th>Play</th><th>Formation</th><th>Alignment</th><th>Key</th><th>Action</th><th>Call/Motion</th></tr>
        </thead>
        <tbody>
          <% @reports.each do |r| %>
            <% key = parse_answer_key(r["answer_key"])[r["play_num"]] || {} %>
            <tr>
              <td><%= h r["player_name"] %></td>
              <td><strong><%= h r["play_num"] %></strong></td>
              <% %w[formation alignment post_key action].each do |field| %>
                <td>
                  <% if key[field].to_s != "" %>
                    <% if r[field].to_s == key[field].to_s %>
                      <span class="correct">✓</span> <%= h r[field] %>
                    <% else %>
                      <span class="wrong">✗</span> <%= h r[field] %>
                      <br><span class="muted" style="font-size:11px;">was: <%= h key[field] %></span>
                    <% end %>
                  <% else %>
                    <%= h r[field] %>
                  <% end %>
                </td>
              <% end %>
              <td class="muted" style="font-size:12px;">
                <% if r["def_call"].to_s != "" %><%= h r["def_call"] %><br><% end %>
                <% if r["motion"].to_s != "" %><%= h r["motion"] %><% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  </div>
<% end %>
