# Storage-Config-Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** tsm synchronisiert `~/.config/tsm/servers` automatisch über die deployte storage-for-agents-Instanz (Pull beim Start, Push bei Änderung, Last-Write-Wins) und der SSH-Sync inkl. Main-Server-Konzept wird entfernt.

**Architecture:** Neues Modul `StorageSync` im Single-File-Skript `tsm` (net/http, presign → PUT/GET). Die TUI startet einen Pull-Thread beim Start und pusht bei Änderungen asynchron. `is_main` verschwindet aus Struct, Dateiformat und UI; Migration passiert beim Parsen.

**Tech Stack:** Ruby Stdlib (net/http, uri, json), storage-for-agents REST-API, tmux + SSH für E2E-Verifikation.

**Spec:** `docs/superpowers/specs/2026-07-03-storage-config-sync-design.md`

**Kontext für den Ausführenden:**
- Das gesamte Tool ist EINE Datei: `/Users/dorra/src/labs/tsm/tsm` (Ruby, kein .rb-Suffix). Es gibt keine Test-Suite; Verifikation läuft über `ruby -c`, Ruby-One-Liner mit Fake-`HOME` und tmux-getriebene E2E-Tests (Spec-Abschnitt "Tests / Verifikation").
- Diese Maschine ist **blue** (machine-id `ec149ee9-8529-45bf-9803-7dff6e3b65fa`). Real konfigurierte Remotes laut `~/.config/tsm/servers`: **spacegrey** (`dorra@macbook-pro.beluga-alpha.ts.net`), **spacestation** (`dorra@spacestation-d1cloud-io`), **studio** (`dorra@mac-mini-dorra.beluga-alpha.ts.net`).
- storage-for-agents-API (siehe `/Users/dorra/src/oona/storage-for-agents/API.md`): `POST /api/buckets/:bucket/objects/presign` mit Bearer liefert `{url, method, expires_at}`; `PUT/GET` auf diese URL überträgt Bytes ohne Auth. Fehlendes Objekt → `404` beim GET auf die presignte URL; fehlender Bucket → `404` beim Presign. `PUT /api/buckets/:name` ist idempotent.
- Die Credentials (Base-URL + `store:`-Bearer) werden in Task 0 über die MCP-Admin-Tools der deployten Instanz provisioniert (`mcp__claude_ai_Administration_Storage-for-Agents__*`).

---

### Task 0: Credentials provisionieren, Smoke-Test, Backups

**Files:** keine Code-Änderung. Erzeugt `~/.config/tsm/config` (lokal) und Backups.

- [ ] **Step 0.1: MCP-Admin-Tools laden und zwei Agents provisionieren**

ToolSearch: `select:mcp__claude_ai_Administration_Storage-for-Agents__tenant_upsert,mcp__claude_ai_Administration_Storage-for-Agents__agent_upsert,mcp__claude_ai_Administration_Storage-for-Agents__agent_get`

Dann:
1. `tenant_upsert(external_ref: "dorra")`
2. `agent_upsert(tenant_ref: "dorra", external_ref: "tsm")` → **PROD-Credentials** (bearer + Base-URL aus `connection.mcp_url` ohne `/mcp`-Suffix)
3. `agent_upsert(tenant_ref: "dorra", external_ref: "tsm-e2e")` → **TEST-Credentials** (eigene Isolation, damit E2E-Tests nie den echten zentralen Stand berühren)

Base-URL und beide Bearer für die folgenden Tasks notieren (Shell-Variablen `$BASE`, `$PROD_TOKEN`, `$TEST_TOKEN`).

- [ ] **Step 0.2: Smoke-Test der REST-API mit dem Test-Token**

```bash
BASE=<base-url>; TEST_TOKEN=<store:...>
curl -sf -X PUT "$BASE/api/buckets/tsm" -H "Authorization: Bearer $TEST_TOKEN"
URL=$(curl -sf -X POST "$BASE/api/buckets/tsm/objects/presign" \
  -H "Authorization: Bearer $TEST_TOKEN" -H 'Content-Type: application/json' \
  -d '{"op":"put","key":"servers","content_type":"text/plain"}' | ruby -r json -e 'puts JSON.parse(STDIN.read)["url"]')
echo "smoke-test" | curl -sf -X PUT "$URL" -H 'Content-Type: text/plain' --data-binary @-
URL=$(curl -sf -X POST "$BASE/api/buckets/tsm/objects/presign" \
  -H "Authorization: Bearer $TEST_TOKEN" -H 'Content-Type: application/json' \
  -d '{"op":"get","key":"servers"}' | ruby -r json -e 'puts JSON.parse(STDIN.read)["url"]')
curl -sf "$URL"   # Expected: smoke-test
```

Expected: letzte Zeile gibt `smoke-test` aus. Falls die presignte URL relativ ist (beginnt mit `/`), das im StorageSync-Code (Task 2) berücksichtigen — der Code dort behandelt beide Fälle bereits.

- [ ] **Step 0.3: Backups anlegen (lokal + alle drei Remotes)**

```bash
cp -R ~/.config/tsm ~/.config/tsm.backup-$(date +%Y%m%d)
for h in dorra@macbook-pro.beluga-alpha.ts.net dorra@spacestation-d1cloud-io dorra@mac-mini-dorra.beluga-alpha.ts.net; do
  ssh -o ConnectTimeout=5 -o BatchMode=yes $h 'cp -R ~/.config/tsm ~/.config/tsm.backup-$(date +%Y%m%d) 2>/dev/null; cp ~/.local/bin/tsm ~/.local/bin/tsm.backup 2>/dev/null; echo "$(hostname): backed up"'
done
```

Expected: drei `backed up`-Zeilen. Nicht erreichbare Hosts notieren — sie fallen aus Task 8 heraus und werden dem Nutzer gemeldet.

- [ ] **Step 0.4: Commit** — nichts zu committen (nur Umgebung). Weiter mit Task 1.

---

### Task 1: `is_main` entfernen + Format-Migration

**Files:**
- Modify: `tsm` (Server-Struct ~Z. 92–114, `ensure_self_entry!` ~Z. 291–298, `add_server_dialog` ~Z. 709–716, `ServerManager` ~Z. 929–1033)

- [ ] **Step 1.1: Server-Struct umbauen**

Ersetze die Struct-Definition (Z. 92–114) durch:

```ruby
# Server configuration struct
Server = Struct.new(:alias_name, :host, :user, :port, :machine_id, keyword_init: true) do
  def local?
    # Check machine_id first (primary method)
    if machine_id && !machine_id.empty?
      return machine_id == MachineId.current
    end
    # Fallback for legacy entries
    host.nil? || host.empty? || host == 'localhost'
  end

  def display_name
    alias_name
  end

  def ssh_target
    return nil if local?
    user && !user.empty? ? "#{user}@#{host}" : host
  end

  def to_line
    "#{alias_name}|#{host || ''}|#{user || ''}|#{port || 22}|#{machine_id || ''}"
  end
end
```

- [ ] **Step 1.2: Alle `Server.new`-Aufrufe von `is_main:` befreien**

In `ensure_self_entry!` (Z. 291–298) und `add_server_dialog` (Z. 709–716) jeweils die Zeile `is_main: false,` löschen. In `ServerManager::DEFAULT_LOCAL` (Z. 932–939) ebenfalls `is_main: false,` löschen.

- [ ] **Step 1.3: `load_servers` mit positionsabhängiger Migration**

Im Parse-Block von `load_servers` (Z. 950–959) ersetzen durch:

```ruby
      parts = line.split('|')
      next if parts.length < 2

      # Legacy 6-column format: alias|host|user|port|is_main|machine_id.
      # New 5-column format has machine_id at index 4. is_main was always
      # literally 'true'/'false'; machine_ids are UUIDs, so no collision.
      machine_id = if parts[4] == 'true' || parts[4] == 'false'
        parts[5]
      else
        parts[4]
      end

      servers << Server.new(
        alias_name: parts[0],
        host: parts[1]&.empty? ? nil : parts[1],
        user: parts[2]&.empty? ? nil : parts[2],
        port: (parts[3] || 22).to_i,
        machine_id: machine_id&.empty? ? nil : machine_id
      )
```

- [ ] **Step 1.4: `save_servers`-Header und `ServerManager`-Rest**

In `save_servers` die Format-Kommentarzeile ändern zu:

```ruby
    content += "# Format: alias|host|user|port|machine_id\n\n"
```

Die Methoden `main_server` und `set_main` (Z. 1021–1028) komplett löschen.

- [ ] **Step 1.5: Verifikation Migration**

```bash
ruby -c tsm   # Expected: Syntax OK
T=$(mktemp -d) && mkdir -p $T/.config/tsm
printf 'a|host-a|u|22|true|11111111-1111-1111-1111-111111111111\nb|host-b|u|22|false|\nc|host-c|u|2222|22222222-2222-2222-2222-222222222222\n' > $T/.config/tsm/servers
HOME=$T ruby -e 'load "./tsm"; s = ServerManager.load_servers; raise "count" unless s.length == 3; raise "mid-legacy" unless s[0].machine_id == "11111111-1111-1111-1111-111111111111"; raise "mid-empty" unless s[1].machine_id.nil?; raise "mid-new-fmt" unless s[2].machine_id == "22222222-2222-2222-2222-222222222222"; raise "port" unless s[2].port == 2222; ServerManager.save_servers(s); puts File.read(File.join(Dir.home, ".config/tsm/servers"))'
```

Expected: Ausgabe zeigt 5-spaltige Zeilen (`a|host-a|u|22|11111111-...`), kein `true`/`false` mehr. Hinweis: `load "./tsm"` führt nur die Definitionen aus (Entry Point ist per `__FILE__ == $0` geschützt).

- [ ] **Step 1.6: Commit**

```bash
git add tsm && git commit -m "Drop is_main from server format (5-column, positional migration)"
```

Achtung: Nach diesem Task referenzieren `set_main_server`/`sync_servers_dialog` (TSM-Klasse) noch gelöschte Methoden — das ist okay, Ruby löst Methoden erst zur Laufzeit auf; `ruby -c` bleibt grün. Task 4 räumt sie ab.

---

### Task 2: `StorageSync`-Modul

**Files:**
- Modify: `tsm` (Konstanten oben ~Z. 16–19; neues Modul direkt nach `UpdateChecker`, vor dem `Installer`-Trennkommentar ~Z. 1317)

- [ ] **Step 2.1: Konstanten ergänzen**

Nach `SSH_TIMEOUT = 5` einfügen:

```ruby
STORAGE_TIMEOUT = 5
STORAGE_BUCKET = 'tsm'
STORAGE_KEY = 'servers'
```

- [ ] **Step 2.2: Modul einfügen** (nach dem Ende von `UpdateChecker`, mit dem üblichen Trennkommentar):

```ruby
# ─────────────────────────────────────────────────────────────
# Storage Sync (config sync via storage-for-agents)
# ─────────────────────────────────────────────────────────────

module StorageSync
  extend self

  def configured?
    c = config
    !!(c[:url] && c[:token])
  end

  def config
    return @config if @config
    url = token = nil
    if File.exist?(CONFIG_FILE)
      content = File.read(CONFIG_FILE)
      url = content[/^storage_url=(.+)$/, 1]&.strip
      token = content[/^storage_token=(.+)$/, 1]&.strip
    end
    @config = { url: url, token: token }
  rescue
    @config = { url: nil, token: nil }
  end

  # Pull servers file. Returns [:ok, content], [:not_found] or [:error].
  def pull
    return [:error] unless configured?

    presigned = presign('get')
    return [:not_found] if presigned == :not_found
    return [:error] unless presigned

    status, body = transfer(:get, presigned)
    case status
    when 200 then mark_synced; [:ok, body]
    when 404 then [:not_found]
    else @state ||= :offline; [:error]
    end
  end

  # Push servers file. Returns true/false.
  def push(content)
    return false unless configured?

    presigned = presign('put')
    if presigned == :not_found
      return false unless ensure_bucket
      presigned = presign('put')
    end
    return false unless presigned && presigned != :not_found

    status, _body = transfer(:put, presigned, body: content)
    if status == 200
      mark_synced
      true
    else
      @state ||= :offline
      false
    end
  end

  def status_line
    return 'no storage configured' unless configured?
    case @state
    when :synced
      age = Time.now.to_i - @synced_at
      age < 60 ? 'synced now' : "synced #{age / 60}m ago"
    when :auth_failed then 'auth failed'
    when :offline then 'offline'
    else 'not synced yet'
    end
  end

  private

  def mark_synced
    @state = :synced
    @synced_at = Time.now.to_i
  end

  def ensure_bucket
    res = api_request(:put, "/api/buckets/#{STORAGE_BUCKET}")
    !res.nil? && [200, 201].include?(res.code.to_i)
  end

  # Returns presigned url (String), :not_found, or nil on error.
  def presign(op)
    require 'json'
    body = { op: op, key: STORAGE_KEY }
    body[:content_type] = 'text/plain' if op == 'put'
    res = api_request(:post, "/api/buckets/#{STORAGE_BUCKET}/objects/presign",
                      body: JSON.generate(body))
    return nil unless res

    case res.code.to_i
    when 200, 201
      url = JSON.parse(res.body)['url'] rescue nil
      return nil unless url
      url.start_with?('/') ? "#{config[:url]}#{url}" : url
    when 401, 403
      @state = :auth_failed
      nil
    when 404
      :not_found
    else
      @state ||= :offline
      nil
    end
  end

  def api_request(method, path, body: nil)
    require 'net/http'
    require 'uri'

    uri = URI.parse("#{config[:url]}#{path}")
    req = method == :put ? Net::HTTP::Put.new(uri.request_uri) : Net::HTTP::Post.new(uri.request_uri)
    req['Authorization'] = "Bearer #{config[:token]}"
    if body
      req['Content-Type'] = 'application/json'
      req.body = body
    end
    http_start(uri) { |http| http.request(req) }
  rescue
    @state = :offline
    nil
  end

  # Returns [status_code, body] or [nil, nil] on network error.
  def transfer(method, url, body: nil)
    require 'net/http'
    require 'uri'

    uri = URI.parse(url)
    req = if method == :put
      r = Net::HTTP::Put.new(uri.request_uri)
      r['Content-Type'] = 'text/plain'
      r.body = body
      r
    else
      Net::HTTP::Get.new(uri.request_uri)
    end
    res = http_start(uri) { |http| http.request(req) }
    [res.code.to_i, res.body]
  rescue
    @state = :offline
    [nil, nil]
  end

  def http_start(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = STORAGE_TIMEOUT
    http.read_timeout = STORAGE_TIMEOUT
    yield http
  end
end
```

- [ ] **Step 2.3: Verifikation gegen die echte Instanz (Test-Agent!)**

```bash
ruby -c tsm   # Expected: Syntax OK
T=$(mktemp -d) && mkdir -p $T/.config/tsm
printf 'storage_url=%s\nstorage_token=%s\n' "$BASE" "$TEST_TOKEN" > $T/.config/tsm/config
HOME=$T ruby -e 'load "./tsm"; raise "conf" unless StorageSync.configured?; raise "push" unless StorageSync.push("x|h|u|22|abc\n"); r = StorageSync.pull; raise "pull #{r.inspect}" unless r == [:ok, "x|h|u|22|abc\n"]; puts StorageSync.status_line'
HOME=$T ruby -e 'load "./tsm"; File.write(File.join(Dir.home, ".config/tsm/config"), "storage_url=http://127.0.0.1:1\nstorage_token=x\n"); r = StorageSync.pull; raise unless r == [:error]; puts StorageSync.status_line'
```

Expected: `synced now`, dann `offline`. (Der Smoke-Test in Task 0 hat das Objekt evtl. schon angelegt — push überschreibt es, das ist gewollt.)

- [ ] **Step 2.4: Commit**

```bash
git add tsm && git commit -m "Add StorageSync module (presign-based config transfer)"
```

---

### Task 3: TUI-Verdrahtung — Pull beim Start, Push bei Änderung

**Files:**
- Modify: `tsm` (`TSM#run` ~Z. 140–171, `handle_input`-Timeout ~Z. 483, neue Methoden neben `start_async_fetch`, `add_server_dialog`, `delete_server_dialog`)
- Modify: `docs/superpowers/specs/2026-07-03-storage-config-sync-design.md` (Push-Zeitpunkte präzisieren)

**Design-Präzisierung gegenüber der Spec** (in der Spec nachziehen, Step 3.5): Die Startup-Normalisierungen (`ensure_self_entry!`, Claim, Migration) pushen NICHT selbst — sie laufen vor dem Pull, und ein Push dort würde bei Last-Write-Wins den evtl. neueren zentralen Stand mit lokalem Alt-Stand überschreiben. Stattdessen: erst pullen; `apply_pulled_config` ergänzt den eigenen Eintrag falls er zentral fehlt und pusht dann. Explizite Pushes nur bei Nutzer-Änderungen (Add/Delete) und beim Seed (`:not_found`).

- [ ] **Step 3.1: Pull-Thread in `run` starten und im Loop einsammeln**

In `TSM#run` nach `start_async_fetch` einfügen: `start_storage_pull`. Im Loop-Zweig `else` vor `check_pending_threads` einfügen: `check_storage_thread`. Ergebnis:

```ruby
    # Start parallel fetch for all servers
    start_async_fetch

    # Pull shared config from storage (async)
    start_storage_pull

    loop do
      if @server_mode
        render_server_menu
        handle_server_input
      else
        check_storage_thread
        check_pending_threads
        @sessions = build_sessions
        render(@sessions)
        handle_input(@sessions)
      end
      break unless @running
    end
```

- [ ] **Step 3.2: Neue Methoden** (direkt nach `check_pending_threads` einfügen):

```ruby
  def start_storage_pull
    return unless StorageSync.configured?
    @storage_thread = Thread.new { StorageSync.pull }
  end

  def check_storage_thread
    return unless @storage_thread
    return if @storage_thread.alive?

    result, content = begin
      @storage_thread.value
    rescue
      [:error]
    end
    @storage_thread = nil

    case result
    when :ok then apply_pulled_config(content)
    when :not_found then push_servers_async # first machine: seed central copy
    end
  end

  def apply_pulled_config(content)
    current = File.exist?(SERVERS_FILE) ? File.read(SERVERS_FILE) : ''
    return if content == current

    self_entry = ServerManager.self_entry(@servers)
    Dir.mkdir(CONFIG_DIR) unless Dir.exist?(CONFIG_DIR)
    File.write(SERVERS_FILE, content)
    @servers = ServerManager.load_servers

    # Central list doesn't know this machine yet - re-add and share
    if self_entry && !ServerManager.self_entry(@servers)
      @servers << self_entry
      ServerManager.save_servers(@servers)
      push_servers_async
    end

    @selected = 0
    start_async_fetch
  end

  def push_servers_async
    return unless StorageSync.configured?
    content = File.read(SERVERS_FILE) rescue nil
    return unless content
    Thread.new { StorageSync.push(content) }
  end
```

- [ ] **Step 3.3: Input-Timeout auch bei laufendem Storage-Thread**

In `handle_input` (Z. 483) ändern zu:

```ruby
    timeout = (@pending_threads.any? || @storage_thread) ? 0.3 : nil
```

- [ ] **Step 3.4: Push bei Nutzer-Änderungen**

In `add_server_dialog` nach `ServerManager.save_servers(@servers)`: Zeile `push_servers_async` einfügen (die bestehende Zeile `push_config_to_server(new_server)` bleibt bis Task 5 stehen). In `delete_server_dialog` nach `ServerManager.save_servers(@servers)` ebenfalls `push_servers_async` einfügen.

- [ ] **Step 3.5: Spec-Absatz anpassen**

In der Spec unter "Push bei Änderung" den Punkt "`ensure_self_entry!` / Claim / Migration, wenn sie die Datei verändert haben" ersetzen durch: "Startup-Normalisierungen pushen nicht selbst (Pull-vor-Push, sonst überschreibt Alt-Stand den zentralen Stand); der eigene Eintrag wird nach dem Pull bei Bedarf ergänzt und dann gepusht."

- [ ] **Step 3.6: Verifikation** — `ruby -c tsm` (Syntax OK). Funktional getestet wird in Task 7 (E2E), weil das Zusammenspiel TTY + Threads nur in tmux realistisch prüfbar ist.

- [ ] **Step 3.7: Commit**

```bash
git add tsm docs/superpowers/specs/2026-07-03-storage-config-sync-design.md
git commit -m "Wire storage sync into TUI: pull on start, push on change"
```

---

### Task 4: SSH-Sync und Main-Server-UI entfernen, Statuszeile

**Files:**
- Modify: `tsm` (`render_server_menu` ~Z. 630–662, `handle_server_input` ~Z. 664–685, Methoden `set_main_server`, `sync_servers_dialog`, `push_config_to_main`, `pull_config_from_main` ~Z. 747–922)

- [ ] **Step 4.1: Methoden löschen**

`set_main_server`, `sync_servers_dialog`, `push_config_to_main`, `pull_config_from_main` komplett entfernen. `push_config_to_server` bleibt noch (wird in Task 5 durch die Token-Verteilung ersetzt).

- [ ] **Step 4.2: `handle_server_input` bereinigen**

Die Zweige `when 'm'` (→ `set_main_server`) und `when 's'` (→ `sync_servers_dialog`) löschen.

- [ ] **Step 4.3: `render_server_menu`: `[main]`-Tag raus, Statuszeile rein, Hilfe kürzen**

Die Zeilen mit `main_tag` ersetzen durch:

```ruby
      name_padded = server.alias_name.ljust(18)

      puts "  #{pointer} #{name_padded}  #{DIM}#{target}#{RESET}"
```

Nach der Server-Schleife (vor `puts` + Hilfezeile) einfügen:

```ruby
    puts
    puts "  #{DIM}sync: #{StorageSync.status_line}#{RESET}"
```

Hilfezeile ersetzen durch:

```ruby
    help_parts = [
      "#{BOLD}↑↓#{RESET} #{DIM}nav#{RESET}",
      "#{CYAN}a#{RESET}#{DIM}dd#{RESET}",
      "#{BOLD}⌫#{RESET} #{DIM}del#{RESET}",
      "#{CYAN}b#{RESET}#{DIM}ack#{RESET}"
    ]
```

- [ ] **Step 4.4: Restsuche** — `grep -n "is_main\|main_server\|set_main\|sync_servers\|pull_config\|push_config_to_main" tsm` → Expected: keine Treffer mehr (nur `push_config_to_server` in `add_server_dialog` + Definition, verschwindet in Task 5). Auch `Installer.show_help` prüfen (`sed -n '1616,1648p' tsm`): falls dort `m`/`s`/Sync erwähnt wird, anpassen.

- [ ] **Step 4.5: Verifikation + Commit**

```bash
ruby -c tsm
git add tsm && git commit -m "Remove SSH sync and main-server UI, show storage sync status"
```

---

### Task 5: Token-Verteilung an neue Server

**Files:**
- Modify: `tsm` (`add_server_dialog`, `push_config_to_server` ersetzen durch `push_storage_config_to_server`)

- [ ] **Step 5.1: `push_config_to_server` ersetzen** durch:

```ruby
  # Copy storage credentials so the new install can sync itself.
  # Only touches storage_url/storage_token; other config keys survive.
  def push_storage_config_to_server(server)
    return if server.local?

    cfg = StorageSync.config
    return unless cfg[:url] && cfg[:token]

    remote_cmd =
      'mkdir -p ~/.config/tsm && touch ~/.config/tsm/config && ' \
      'grep -v -e ^storage_url= -e ^storage_token= ~/.config/tsm/config > ~/.config/tsm/config.tmp; ' \
      "echo \"storage_url=#{cfg[:url]}\" >> ~/.config/tsm/config.tmp && " \
      "echo \"storage_token=#{cfg[:token]}\" >> ~/.config/tsm/config.tmp && " \
      'mv ~/.config/tsm/config.tmp ~/.config/tsm/config'

    print CLEAR
    puts "  #{DIM}Pushing storage credentials to #{server.alias_name}...#{RESET}"

    if system(RemoteExecutor.build_ssh_command(server, remote_cmd))
      puts "\n  #{GREEN}Credentials pushed to #{server.alias_name}#{RESET}\n"
    else
      puts "\n  #{RED}Credential push failed#{RESET}\n"
    end

    sleep 1
  end
```

(Kein Single-Quote im `remote_cmd` — `build_ssh_command` wrappt in Single-Quotes. Die grep-Pattern sind bewusst unquoted.)

- [ ] **Step 5.2: Aufrufer anpassen** — in `add_server_dialog` die Zeile `push_config_to_server(new_server)` ersetzen durch `push_storage_config_to_server(new_server)`.

- [ ] **Step 5.3: Verifikation** (idempotent, gegen einen echten Remote, nutzt das Backup aus Task 0):

```bash
ruby -c tsm
HOME_REAL_TEST=$(mktemp -d) && mkdir -p $HOME_REAL_TEST/.config/tsm
printf 'storage_url=%s\nstorage_token=%s\n' "$BASE" "$TEST_TOKEN" > $HOME_REAL_TEST/.config/tsm/config
HOME=$HOME_REAL_TEST ruby -e 'load "./tsm"; s = Server.new(alias_name: "spacegrey", host: "macbook-pro.beluga-alpha.ts.net", user: "dorra", port: 22, machine_id: "x"); TSM.new.send(:push_storage_config_to_server, s)'
ssh -o BatchMode=yes dorra@macbook-pro.beluga-alpha.ts.net 'grep -c storage_ ~/.config/tsm/config'   # Expected: 2
# Zweiter Lauf → immer noch 2 (idempotent, keine Duplikate)
```

- [ ] **Step 5.4: Commit**

```bash
git add tsm && git commit -m "Distribute storage credentials to new server installs"
```

---

### Task 6: README + Version 1.10.0

**Files:**
- Modify: `tsm` (Z. 7: `VERSION = '1.10.0'`)
- Modify: `README.md`

- [ ] **Step 6.1: Version bump** — `VERSION = '1.10.0'`.

- [ ] **Step 6.2: README anpassen**

- Features: "Server configuration sync — bidirectional sync with main server" → "Server configuration sync — automatic via a central storage service".
- Keybindings "Server Config": `m`- und `s`-Zeilen entfernen.
- Abschnitt "Server Configuration": Format-Beispiel auf 5 Spalten (`alias|host|user|port|machine_id`, echte UUID-Beispiele) korrigieren — das README zeigt heute fälschlich `is_main` als letzte Spalte.
- Abschnitt "Sync" ersetzen: Config wird automatisch beim Start gepullt und bei jeder Änderung gepusht; Voraussetzung sind `storage_url`/`storage_token` in `~/.config/tsm/config`; Last-Write-Wins; ohne Keys läuft tsm lokal.
- Abschnitt "Configuration": die zwei neuen Keys dokumentieren:

```
update_url=https://raw.githubusercontent.com/dorra/tsm/main/tsm
storage_url=https://storage.example.com
storage_token=store:...
```

- [ ] **Step 6.3: Commit**

```bash
git add tsm README.md && git commit -m "Update README for storage sync, bump to v1.10.0"
```

---

### Task 7: Lokale E2E-Verifikation (tmux, zwei Fake-HOMEs, Test-Agent)

**Files:** keine Änderung — reine Verifikation. Bei Fehlern: fixen, committen, Task wiederholen.

Setup: Zwei Fake-HOMEs simulieren zwei Maschinen; beide nutzen den **Test**-Agent (`tsm-e2e`), damit der echte zentrale Stand unberührt bleibt.

- [ ] **Step 7.1: Fake-Maschinen anlegen**

```bash
E2E=/tmp/tsm-e2e && rm -rf $E2E && mkdir -p $E2E/a/.config/tsm $E2E/b/.config/tsm
MID_A=$(uuidgen | tr A-Z a-z); MID_B=$(uuidgen | tr A-Z a-z)
echo $MID_A > $E2E/a/.config/tsm/machine-id
echo $MID_B > $E2E/b/.config/tsm/machine-id
for h in a b; do printf 'storage_url=%s\nstorage_token=%s\n' "$BASE" "$TEST_TOKEN" > $E2E/$h/.config/tsm/config; done
printf 'fake-a|localhost|%s|22|%s\nfake-b|localhost|%s|22|%s\nstale|stale.example.com|x|22|\n' "$USER" "$MID_A" "$USER" "$MID_B" > $E2E/a/.config/tsm/servers
printf 'fake-b|localhost|%s|22|%s\n' "$USER" "$MID_B" > $E2E/b/.config/tsm/servers
# Zentralen Test-Stand zurücksetzen: Objekt mit A-Liste seeden passiert durch A selbst (:not_found → seed)
curl -sf -X DELETE "$BASE/api/buckets/tsm/objects/servers" -H "Authorization: Bearer $TEST_TOKEN" || true
```

- [ ] **Step 7.2: "Maschine A" starten, Seed prüfen, Server löschen**

```bash
tmux kill-session -t tsm-e2e-a 2>/dev/null; tmux new-session -d -s tsm-e2e-a -x 100 -y 30 "env HOME=$E2E/a ruby $PWD/tsm"
sleep 4 && tmux send-keys -t tsm-e2e-a c && sleep 1 && tmux capture-pane -t tsm-e2e-a -p
```

Expected: Server-Menü mit `fake-a`, `fake-b`, `stale`, Statuszeile `sync: synced now` (Seed durch `:not_found`), **kein** `[main]`, Hilfe ohne `m`/`s`. Dann `stale` löschen (j/j navigieren bis `stale` selektiert, Backspace, y):

```bash
tmux send-keys -t tsm-e2e-a j j && tmux send-keys -t tsm-e2e-a BSpace && sleep 1 && tmux send-keys -t tsm-e2e-a y && sleep 2 && tmux capture-pane -t tsm-e2e-a -p
```

Expected: `stale` weg. Zentralen Stand prüfen (presign get + curl wie Task 0): Objekt enthält `fake-a` und `fake-b`, kein `stale`.

- [ ] **Step 7.3: "Maschine B" starten — Pull übernimmt A-Stand**

```bash
tmux kill-session -t tsm-e2e-b 2>/dev/null; tmux new-session -d -s tsm-e2e-b -x 100 -y 30 "env HOME=$E2E/b ruby $PWD/tsm"
sleep 4 && tmux send-keys -t tsm-e2e-b c && sleep 1 && tmux capture-pane -t tsm-e2e-b -p
cat $E2E/b/.config/tsm/servers
```

Expected: B zeigt `fake-a` + `fake-b`, `sync: synced`; Datei in B ist der zentrale Stand.

- [ ] **Step 7.4: Offline- und Unconfigured-Fälle**

```bash
sed -i '' 's|^storage_url=.*|storage_url=http://127.0.0.1:1|' $E2E/b/.config/tsm/config
tmux kill-session -t tsm-e2e-b; tmux new-session -d -s tsm-e2e-b -x 100 -y 30 "env HOME=$E2E/b ruby $PWD/tsm"
sleep 8 && tmux send-keys -t tsm-e2e-b c && sleep 1 && tmux capture-pane -t tsm-e2e-b -p | grep sync:   # Expected: sync: offline (oder not synced yet)
grep -v storage_ $E2E/b/.config/tsm/config > $E2E/b/.config/tsm/config.new && mv $E2E/b/.config/tsm/config.new $E2E/b/.config/tsm/config
tmux kill-session -t tsm-e2e-b; tmux new-session -d -s tsm-e2e-b -x 100 -y 30 "env HOME=$E2E/b ruby $PWD/tsm"
sleep 3 && tmux send-keys -t tsm-e2e-b c && sleep 1 && tmux capture-pane -t tsm-e2e-b -p | grep sync:   # Expected: sync: no storage configured
```

- [ ] **Step 7.5: Aufräumen + Commit (falls Fixes anfielen)**

```bash
tmux kill-session -t tsm-e2e-a 2>/dev/null; tmux kill-session -t tsm-e2e-b 2>/dev/null; rm -rf $E2E
```

---

### Task 8: Rollout + Verifikation über die echten Rechner

**Files:** keine Code-Änderung. Betrifft blue (lokal), spacegrey, spacestation, studio.

- [ ] **Step 8.1: PROD-Credentials lokal eintragen**

```bash
touch ~/.config/tsm/config
grep -v -e ^storage_url= -e ^storage_token= ~/.config/tsm/config > /tmp/tsm-config.tmp || true
printf 'storage_url=%s\nstorage_token=%s\n' "$BASE" "$PROD_TOKEN" >> /tmp/tsm-config.tmp
mv /tmp/tsm-config.tmp ~/.config/tsm/config
```

- [ ] **Step 8.2: Neues Binary + Credentials auf alle Remotes**

```bash
for h in dorra@macbook-pro.beluga-alpha.ts.net dorra@spacestation-d1cloud-io dorra@mac-mini-dorra.beluga-alpha.ts.net; do
  scp -o BatchMode=yes ./tsm $h:.local/bin/tsm
  ssh -o BatchMode=yes $h 'chmod +x ~/.local/bin/tsm; mkdir -p ~/.config/tsm; touch ~/.config/tsm/config; grep -v -e ^storage_url= -e ^storage_token= ~/.config/tsm/config > ~/.config/tsm/config.tmp; printf "storage_url='"$BASE"'\nstorage_token='"$PROD_TOKEN"'\n" >> ~/.config/tsm/config.tmp; mv ~/.config/tsm/config.tmp ~/.config/tsm/config; ~/.local/bin/tsm --version'
done
```

Expected: je Host `tsm v1.10.0`. Offline-Hosts überspringen und am Ende dem Nutzer melden.

- [ ] **Step 8.3: Lokal (blue) starten — seeded den zentralen Stand**

Wie Task 7, aber echtes HOME, in einer eigenen tmux-Session (`tsm-verify`): starten, 5 s warten, `c`, capture-pane → Expected: alle 4 Server, `sync: synced`, kein `[main]`. Session danach beenden (`q` senden, kill-session). Zentralen PROD-Stand per presign-get prüfen: 4 Zeilen, 5-spaltig.

- [ ] **Step 8.4: Jeden Remote einmal starten und Sync prüfen**

Pro Host (Beispiel spacegrey):

```bash
H=dorra@macbook-pro.beluga-alpha.ts.net
ssh -o BatchMode=yes $H 'export PATH=/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH; tmux kill-session -t tsm-verify 2>/dev/null; tmux new-session -d -s tsm-verify -x 100 -y 30 "~/.local/bin/tsm"'
sleep 6
ssh -o BatchMode=yes $H 'export PATH=/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH; tmux send-keys -t tsm-verify c; sleep 1; tmux capture-pane -t tsm-verify -p; tmux kill-session -t tsm-verify'
ssh -o BatchMode=yes $H 'cat ~/.config/tsm/servers'
```

Expected: capture zeigt `sync: synced` + alle 4 Server; die Datei ist byte-identisch mit dem zentralen Stand (5-spaltig, kein `true`/`false`).

- [ ] **Step 8.5: Abschlussprüfung Konsistenz**

Alle vier `~/.config/tsm/servers` (blue lokal + 3 Remotes) vergleichen → identischer Inhalt. Ergebnis inkl. evtl. nicht erreichbarer Hosts dem Nutzer berichten.

- [ ] **Step 8.6: Hinweis für den Nutzer festhalten**

Im Abschlussbericht erwähnen: `tsm --update` auf den Remotes zieht von GitHub (`UPDATE_URL_DEFAULT`) — solange v1.10.0 nicht gepusht ist, würde ein `--update` die Remotes auf v1.9.5 zurücksetzen. Push auf GitHub ist Entscheidung des Nutzers.

---

## Self-Review (durchgeführt beim Schreiben)

- **Spec-Abdeckung:** Bucket/Key (T2), net/http-Transport (T2), Config-Keys + lokaler Modus (T2/T4-Statuszeile), Pull beim Start + Self-Entry-Nachtrag (T3), Push bei Änderung + LWW + Seed bei 404 (T3), Rückbau inkl. `display_name`/`m`/`s` (T1/T4), Format-Migration (T1), Token-Verteilung (T5), README/Statuszeile (T4/T6), Fehlerbehandlung/Timeouts/auth failed (T2), manuelle Verifikation inkl. Offline/Unconfigured/Legacy-Format (T7/T8). Eine bewusste Spec-Abweichung (Startup-Pushes) wird in T3.5 in die Spec zurückgeschrieben.
- **Offener Spec-Punkt (Credentials):** durch T0 (MCP-Provisionierung) gelöst.
- **Typ-Konsistenz:** `StorageSync.pull` → `[:ok, content] | [:not_found] | [:error]`; `push(content) → bool`; `status_line → String`; `config → {url:, token:}` — Verwendung in T3/T4/T5 stimmt damit überein.
