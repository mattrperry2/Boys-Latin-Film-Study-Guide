require 'sinatra'
require 'csv'

set :bind, '0.0.0.0'
set :port, ENV['PORT'] || 4568

# --- ROUTES (The Hallways) ---
get '/' do erb :lobby end
get '/lb' do erb :lb_form end
get '/dl' do erb :dl_form end
get '/cb' do erb :cb_form end
get '/safety' do erb :safety_form end

# --- THE COACHES OFFICE (Analytics Dashboard) ---
get '/office' do
  file_path = "scouting_report.csv"
  @reports = []
  @total_reps = 0
  @lb_reps = 0
  @dl_reps = 0
  @cb_reps = 0
  @safety_reps = 0
  
  if File.exist?(file_path)
    @reports = CSV.read(file_path, headers: true)
    @total_reps = @reports.length
    
    # Calculate stats for the dashboard
    @reports.each do |row|
      room = row["Room"].to_s
      @lb_reps += 1 if room.include?("Linebacker")
      @dl_reps += 1 if room.include?("D-Line")
      @cb_reps += 1 if room.include?("CB")
      @safety_reps += 1 if room.include?("Safety")
    end
  end
  
  erb :office
end

# --- CLEAR FILM (Delete Database) ---
post '/clear_film' do
  File.delete("scouting_report.csv") if File.exist?("scouting_report.csv")
  redirect '/office'
end

# --- THE ENGINE & DATABASE (Save the Data) ---
post '/submit' do
  @timestamp = params[:timestamp]
  @offense = params[:offense]
  @gap = params[:gap]
  @room = params[:room]
  @position = params[:position]

  read1 = ""
  read2 = ""

  if @room == "Kuechly Linebacker Room"
    read1 = params[:guard_key]
    read2 = params[:back_flow]
    if read1.include?("Pulled") && read2.include?("Split")
      @rule = "COUNTER/TRAP. Scrape over the top and spill!"
    elsif read1.include?("Pass") || read2.include?("Pass")
      @rule = "High hat. Drop to hook/curl zone. Eyes on QB."
    elsif read1.include?("Base") && read2.include?("Fast")
      @rule = "Downhill now! Fill your gap immediately!"
    else
      @rule = "Read flow and fit your gap. Play fast!"
    end

  elsif @room == "Donald D-Line Room"
    read1 = params[:key1]
    read2 = params[:key2]
    if @position.include?("End")
      if read1.include?("Down")
        @rule = "Tackle blocked down. Crash down, spill the kickout!"
      elsif read1.include?("Pass")
        @rule = "High Hat. Speed rush the edge, contain the QB!"
      else
        @rule = "Set the edge, keep your outside arm free!"
      end
    else
      if read1.include?("Down") && read2.include?("Away")
        @rule = "BACK BLOCK. Anchor your gap, squeeze the puller!"
      elsif read1.include?("Double")
        @rule = "DOUBLE TEAM. Drop your hips, fight pressure!"
      elsif read1.include?("Pass")
        @rule = "HIGH HAT. Convert to pass rush! Get to the QB."
      else
        @rule = "Strike the breastplate, control your gap!"
      end
    end

  elsif @room == "Deion CB Room"
    read1 = params[:release]
    read2 = params[:qb_drop]
    if read1.include?("Inside") && read2.include?("3-step")
      @rule = "SLANT. Plant and drive on the inside hip!"
    elsif read1.include?("Vertical") && read2.include?("5-step")
      @rule = "DEEP THREAT. Stay in phase, play the pocket!"
    elsif read2.include?("Play Action")
      @rule = "RUN READ. Check your run force responsibility!"
    else
      @rule = "Read the hips, stay sticky, own your zone."
    end

  elsif @room == "Reed Safety Room"
    read1 = params[:oline]
    read2 = params[:routes]
    if read1.include?("Low Hat")
      @rule = "RUN. Fill the alley, come to balance, make the tackle!"
    elsif read2.include?("Crossing")
      @rule = "CROSSERS. Communicate, pass it off, or jump the route!"
    else
      @rule = "PASS. Get depth, read the QB's eyes, make a play!"
    end
  end

  # Save to the CSV Spreadsheet
  file_path = "scouting_report.csv"
  headers = ["Timestamp", "Room", "Position", "Offensive Formation", "Pre-Snap Gap", "Primary Key", "Secondary Key", "Execution Rule"]
  
  unless File.exist?(file_path)
    CSV.open(file_path, "w") { |csv| csv << headers }
  end

  CSV.open(file_path, "a") do |csv|
    csv << [@timestamp, @room, @position, @offense, @gap, read1, read2, @rule]
  end

  erb :result
end

__END__

@@lobby
<!DOCTYPE html>
<body style="font-family: -apple-system, sans-serif; background: #0f172a; color: #f8fafc; text-align: center; padding: 50px;">
  <h1 style="color: #ef4444;">🏈 Defensive Team Facility</h1>
  <p style="font-size: 18px; color: #94a3b8;">Which position room are you entering?</p>
  
  <div style="max-width: 400px; margin: 0 auto;">
    <a href="/office" style="display: block; padding: 15px; margin: 15px 0 30px 0; background: #3b82f6; color: white; text-decoration: none; border-radius: 8px; font-weight: bold; border: 2px solid #60a5fa;">📋 Enter Coaches Office (Film Reports)</a>
    
    <a href="/lb" style="display: block; padding: 15px; margin: 15px 0; background: #1e293b; color: white; text-decoration: none; border-radius: 8px; font-weight: bold; border-left: 4px solid #ef4444;">🛡️ Kuechly Linebacker Room</a>
    <a href="/dl" style="display: block; padding: 15px; margin: 15px 0; background: #1e293b; color: white; text-decoration: none; border-radius: 8px; font-weight: bold; border-left: 4px solid #38bdf8;">⚓ Donald D-Line Room</a>
    <a href="/cb" style="display: block; padding: 15px; margin: 15px 0; background: #1e293b; color: white; text-decoration: none; border-radius: 8px; font-weight: bold; border-left: 4px solid #facc15;">🔒 Deion CB Room</a>
    <a href="/safety" style="display: block; padding: 15px; margin: 15px 0; background: #1e293b; color: white; text-decoration: none; border-radius: 8px; font-weight: bold; border-left: 4px solid #22c55e;">🦅 Reed Safety Room</a>
  </div>
</body>

@@office
<!DOCTYPE html>
<body style="font-family: -apple-system, sans-serif; background: #0f172a; color: #f8fafc; padding: 20px;">
  <div style="max-width: 1000px; margin: 0 auto;">
    
    <div style="display: flex; justify-content: space-between; align-items: center; border-bottom: 2px solid #3b82f6; padding-bottom: 10px; margin-bottom: 20px;">
      <h1 style="color: #3b82f6; margin: 0;">📋 Head Coach Dashboard</h1>
      <a href="/" style="padding: 10px 20px; background: #334155; color: white; text-decoration: none; border-radius: 4px; font-weight: bold;">&larr; Facility Lobby</a>
    </div>

    <div style="display: flex; gap: 15px; margin-bottom: 20px; flex-wrap: wrap;">
      <div style="background: #1e293b; padding: 15px; border-radius: 8px; flex: 1; text-align: center; border-top: 4px solid #3b82f6;">
        <h3 style="margin: 0; color: #94a3b8;">Total Reps</h3>
        <p style="font-size: 24px; font-weight: bold; margin: 10px 0 0 0;"><%= @total_reps %></p>
      </div>
      <div style="background: #1e293b; padding: 15px; border-radius: 8px; flex: 1; text-align: center; border-top: 4px solid #ef4444;">
        <h3 style="margin: 0; color: #94a3b8;">Linebackers</h3>
        <p style="font-size: 24px; font-weight: bold; margin: 10px 0 0 0;"><%= @lb_reps %></p>
      </div>
      <div style="background: #1e293b; padding: 15px; border-radius: 8px; flex: 1; text-align: center; border-top: 4px solid #38bdf8;">
        <h3 style="margin: 0; color: #94a3b8;">D-Line</h3>
        <p style="font-size: 24px; font-weight: bold; margin: 10px 0 0 0;"><%= @dl_reps %></p>
      </div>
      <div style="background: #1e293b; padding: 15px; border-radius: 8px; flex: 1; text-align: center; border-top: 4px solid #facc15;">
        <h3 style="margin: 0; color: #94a3b8;">Corners</h3>
        <p style="font-size: 24px; font-weight: bold; margin: 10px 0 0 0;"><%= @cb_reps %></p>
      </div>
      <div style="background: #1e293b; padding: 15px; border-radius: 8px; flex: 1; text-align: center; border-top: 4px solid #22c55e;">
        <h3 style="margin: 0; color: #94a3b8;">Safeties</h3>
        <p style="font-size: 24px; font-weight: bold; margin: 10px 0 0 0;"><%= @safety_reps %></p>
      </div>
    </div>
    
    <% if @reports.empty? %>
      <div style="background: #1e293b; padding: 30px; text-align: center; border-radius: 8px; margin-top: 20px;">
        <h2 style="color: #94a3b8;">No film studied yet.</h2>
        <p>Send your players to the facility to log some reps!</p>
      </div>
    <% else %>
      <div style="background: #1e293b; border-radius: 8px; padding: 20px;">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px;">
          <h2 style="margin: 0; color: #f8fafc;">Master Film Log</h2>
          <form action="/clear_film" method="post" onsubmit="return confirm('WARNING: Are you sure you want to delete all film logs and start a new week?');">
            <input type="submit" value="🗑️ Clear Data for New Week" style="padding: 8px 15px; background: #ef4444; color: white; border: none; border-radius: 4px; font-weight: bold; cursor: pointer;">
          </form>
        </div>
        <div style="overflow-x: auto;">
          <table style="width: 100%; border-collapse: collapse;">
            <thead style="background: #334155; text-align: left;">
              <tr>
                <th style="padding: 12px; border-bottom: 1px solid #475569;">Time</th>
                <th style="padding: 12px; border-bottom: 1px solid #475569;">Room</th>
                <th style="padding: 12px; border-bottom: 1px solid #475569;">Vs. Offense</th>
                <th style="padding: 12px; border-bottom: 1px solid #475569;">Pre-Snap Gap</th>
                <th style="padding: 12px; border-bottom: 1px solid #475569;">Key 1</th>
                <th style="padding: 12px; border-bottom: 1px solid #475569;">Key 2</th>
                <th style="padding: 12px; border-bottom: 1px solid #475569;">Execution Rule</th>
              </tr>
            </thead>
            <tbody>
              <% @reports.each do |row| %>
                <tr>
                  <td style="padding: 12px; border-bottom: 1px solid #334155;"><%= row["Timestamp"] %></td>
                  <td style="padding: 12px; border-bottom: 1px solid #334155; font-weight: bold; color: #94a3b8;"><%= row["Room"].to_s.split(' ').first %></td>
                  <td style="padding: 12px; border-bottom: 1px solid #334155; color: #facc15;"><%= row["Offensive Formation"] %></td>
                  <td style="padding: 12px; border-bottom: 1px solid #334155;"><%= row["Pre-Snap Gap"] %></td>
                  <td style="padding: 12px; border-bottom: 1px solid #334155;"><%= row["Primary Key"] %></td>
                  <td style="padding: 12px; border-bottom: 1px solid #334155;"><%= row["Secondary Key"] %></td>
                  <td style="padding: 12px; border-bottom: 1px solid #334155; color: #ef4444;"><%= row["Execution Rule"] %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    <% end %>
  </div>
</body>

@@lb_form
<!DOCTYPE html>
<body style="font-family: -apple-system, sans-serif; background: #0f172a; color: #f8fafc; padding: 20px; max-width: 600px; margin: 0 auto;">
  <h1 style="color: #ef4444;">🛡️ Kuechly Linebacker Room</h1>
  <form action="/submit" method="post" style="background: #1e293b; padding: 20px; border-radius: 8px;">
    <input type="hidden" name="room" value="Kuechly Linebacker Room">
    <label><strong>Timestamp:</strong></label><br><input type="text" name="timestamp" placeholder="e.g., 1:04" style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;"><br>
    
    <label><strong>Offensive Formation:</strong></label><br>
    <input list="offense_list" name="offense" placeholder="Select or type a formation..." style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;">
    <datalist id="offense_list">
      <option value="2x2 Spread">
      <option value="3x1 Trips">
      <option value="Empty (5-Wide)">
      <option value="Pro I-Formation">
      <option value="Singleback (12 Personnel)">
      <option value="Heavy (22 Personnel)">
      <option value="Wing-T">
    </datalist><br>

    <label><strong>Position:</strong></label><br><select name="position" style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;"><option>Mike</option><option>Will</option></select><br>
    <label><strong>Pre-Snap Gap:</strong></label><br><select name="gap" style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;"><option>Strong A-Gap</option><option>Weak A-Gap</option><option>Strong B-Gap</option><option>Weak B-Gap</option><option>C-Gap</option></select><br>
    <label><strong>1. Guard Key:</strong></label><br><select name="guard_key" style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;"><option>Base (Fired out)</option><option>Pulled (Across center)</option><option>Pass Set (High Hat)</option></select><br>
    <label><strong>2. Backfield Flow:</strong></label><br><select name="back_flow" style="width: 100%; padding: 8px; margin: 5px 0 20px 0; border-radius: 4px; box-sizing: border-box;"><option>Fast Flow</option><option>Split Flow</option><option>Pass Pro</option></select><br>
    <input type="submit" value="Get Execution Rule" style="width: 100%; padding: 12px; background: #ef4444; color: white; font-weight: bold; border: none; border-radius: 4px; cursor: pointer;">
  </form>
</body>

@@dl_form
<!DOCTYPE html>
<body style="font-family: -apple-system, sans-serif; background: #0f172a; color: #f8fafc; padding: 20px; max-width: 600px; margin: 0 auto;">
  <h1 style="color: #38bdf8;">⚓ Donald D-Line Room</h1>
  <form action="/submit" method="post" style="background: #1e293b; padding: 20px; border-radius: 8px;">
    <input type="hidden" name="room" value="Donald D-Line Room">
    <label><strong>Timestamp:</strong></label><br><input type="text" name="timestamp" style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;"><br>
    
    <label><strong>Offensive Formation:</strong></label><br>
    <input list="offense_list" name="offense" placeholder="Select or type a formation..." style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;">
    <datalist id="offense_list">
      <option value="2x2 Spread">
      <option value="3x1 Trips">
      <option value="Empty (5-Wide)">
      <option value="Pro I-Formation">
      <option value="Singleback (12 Personnel)">
      <option value="Heavy (22 Personnel)">
      <option value="Wing-T">
    </datalist><br>

    <label><strong>Position:</strong></label><br><select name="position" style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;"><option>Defensive Tackle (1/3-Tech)</option><option>Defensive End (Edge)</option></select><br>
    <label><strong>Pre-Snap Gap:</strong></label><br><select name="gap" style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;"><option>A-Gap</option><option>B-Gap</option><option>C-Gap</option><option>D-Gap (Edge)</option></select><br>
    <label><strong>1. Primary Key:</strong></label><br><select name="key1" style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;"><option>Base Block</option><option>Down Block</option><option>Double Team</option><option>Pass Set</option></select><br>
    <label><strong>2. Secondary Key:</strong></label><br><select name="key2" style="width: 100%; padding: 8px; margin: 5px 0 20px 0; border-radius: 4px; box-sizing: border-box;"><option>Flow Towards / Reach</option><option>Flow Away / Pulled</option><option>Pass Protection</option></select><br>
    <input type="submit" value="Get Trench Rule" style="width: 100%; padding: 12px; background: #38bdf8; color: white; font-weight: bold; border: none; border-radius: 4px; cursor: pointer;">
  </form>
</body>

@@cb_form
<!DOCTYPE html>
<body style="font-family: -apple-system, sans-serif; background: #0f172a; color: #f8fafc; padding: 20px; max-width: 600px; margin: 0 auto;">
  <h1 style="color: #facc15;">🔒 Deion CB Room</h1>
  <form action="/submit" method="post" style="background: #1e293b; padding: 20px; border-radius: 8px;">
    <input type="hidden" name="room" value="Deion CB Room">
    <label><strong>Timestamp:</strong></label><br><input type="text" name="timestamp" style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;"><br>
    
    <label><strong>Offensive Formation:</strong></label><br>
    <input list="offense_list" name="offense" placeholder="Select or type a formation..." style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;">
    <datalist id="offense_list">
      <option value="2x2 Spread">
      <option value="3x1 Trips">
      <option value="Empty (5-Wide)">
      <option value="Pro I-Formation">
      <option value="Singleback (12 Personnel)">
      <option value="Heavy (22 Personnel)">
      <option value="Wing-T">
    </datalist><br>

    <label><strong>Position:</strong></label><br><select name="position" style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;"><option>Field CB</option><option>Boundary CB</option><option>Nickel</option></select><br>
    <label><strong>Coverage Zone:</strong></label><br><select name="gap" style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;"><option>Deep Third</option><option>Flat</option><option>Man-to-Man</option></select><br>
    <label><strong>1. WR Release:</strong></label><br><select name="release" style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;"><option>Inside Release</option><option>Outside Release</option><option>Vertical Release</option></select><br>
    <label><strong>2. QB Drop:</strong></label><br><select name="qb_drop" style="width: 100%; padding: 8px; margin: 5px 0 20px 0; border-radius: 4px; box-sizing: border-box;"><option>3-step drop</option><option>5-step drop</option><option>Play Action</option></select><br>
    <input type="submit" value="Get Coverage Rule" style="width: 100%; padding: 12px; background: #facc15; color: #0f172a; font-weight: bold; border: none; border-radius: 4px; cursor: pointer;">
  </form>
</body>

@@safety_form
<!DOCTYPE html>
<body style="font-family: -apple-system, sans-serif; background: #0f172a; color: #f8fafc; padding: 20px; max-width: 600px; margin: 0 auto;">
  <h1 style="color: #22c55e;">🦅 Reed Safety Room</h1>
  <form action="/submit" method="post" style="background: #1e293b; padding: 20px; border-radius: 8px;">
    <input type="hidden" name="room" value="Reed Safety Room">
    <label><strong>Timestamp:</strong></label><br><input type="text" name="timestamp" style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;"><br>
    
    <label><strong>Offensive Formation:</strong></label><br>
    <input list="offense_list" name="offense" placeholder="Select or type a formation..." style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;">
    <datalist id="offense_list">
      <option value="2x2 Spread">
      <option value="3x1 Trips">
      <option value="Empty (5-Wide)">
      <option value="Pro I-Formation">
      <option value="Singleback (12 Personnel)">
      <option value="Heavy (22 Personnel)">
      <option value="Wing-T">
    </datalist><br>

    <label><strong>Position:</strong></label><br><select name="position" style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;"><option>Free Safety</option><option>Strong Safety</option></select><br>
    <label><strong>Coverage Zone/Force:</strong></label><br><select name="gap" style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;"><option>Deep Half</option><option>Middle of Field</option><option>Alley Defender (Force)</option></select><br>
    <label><strong>1. O-Line Read:</strong></label><br><select name="oline" style="width: 100%; padding: 8px; margin: 5px 0 15px 0; border-radius: 4px; box-sizing: border-box;"><option>Low Hat (Run)</option><option>High Hat (Pass)</option></select><br>
    <label><strong>2. Route Concept:</strong></label><br><select name="routes" style="width: 100%; padding: 8px; margin: 5px 0 20px 0; border-radius: 4px; box-sizing: border-box;"><option>Vertical / Seams</option><option>Crossing / Digs</option><option>Out / Flats</option></select><br>
    <input type="submit" value="Get Safety Rule" style="width: 100%; padding: 12px; background: #22c55e; color: white; font-weight: bold; border: none; border-radius: 4px; cursor: pointer;">
  </form>
</body>

@@result
<!DOCTYPE html>
<body style="font-family: -apple-system, sans-serif; background: #0f172a; color: #f8fafc; padding: 20px; max-width: 600px; margin: 0 auto; text-align: center;">
  <h1 style="color: #22c55e;">✅ Post-Snap Execution</h1>
  <div style="background: #1e293b; padding: 20px; border-radius: 8px; text-align: left; display: inline-block; width: 100%; box-sizing: border-box;">
    <p><strong>Vs:</strong> <%= @offense %> | <strong>Pre-Snap:</strong> <%= @gap %></p>
    <h2 style="color: #f1f5f9; border-top: 1px solid #334155; padding-top: 15px; margin-top: 15px; line-height: 1.4;">RULE: <span style="color: #ef4444;"><%= @rule %></span></h2>
    <p style="color: #94a3b8; font-size: 14px; margin-top: 20px;">💾 <em>Play fully logged to spreadsheet.</em></p>
  </div>
  <br><br><a href="/" style="display: inline-block; padding: 10px 20px; background: #334155; color: white; text-decoration: none; border-radius: 4px; font-weight: bold;">&larr; Return to Facility Lobby</a>
</body>
