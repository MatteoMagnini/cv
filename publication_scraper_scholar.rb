require 'mechanize'
require 'bibtex'
require 'nokogiri'
require 'uri'
require 'fileutils'
require 'securerandom'
require 'fuzzystringmatch'
require 'time'
require 'digest'

# === CONFIG ===
SCHOLAR_USER_ID = 'iJDPEaUAAAAJ'
BIB_FILE = 'bibliography.bib'
BACKUP_DIR = 'backups'
MAX_REQUESTS_BEFORE_LONG_SLEEP = 15
LONG_SLEEP_SECONDS = 90..150
MIN_DELAY = 2
MAX_DELAY = 6
PROXY_LIST = [] # ['http://user:pass@proxy:port', ...]

# === UTILITIES ===
def random_ip
  loop do
    ip = [
      rand(1..223),
      rand(0..255),
      rand(0..255),
      rand(1..254)
    ]
    return ip.join('.') unless [10, 127, 169, 172, 192].include?(ip[0])
  end
end

def random_user_agent
  ip = random_ip
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64; IP=#{ip}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/#{rand(80..120)}.0.#{rand(1000..4000)}.#{rand(100..200)} Safari/537.36"
end

def download_html(url)
  URI.open(url,
    'User-Agent' => random_user_agent,
    'Accept-Language' => 'en-US,en;q=0.9'
  ) { |resp| Nokogiri::HTML(resp.read) }
rescue => e
  warn "Failed to download #{url}: #{e}"
  nil
end

def read_exclude_titles(file)
  return [] unless File.exist?(file)
  File.readlines(file, encoding: 'UTF-8').map(&:strip).map { |t| normalize_title(t) }.uniq
end

REFERERS = [
  'https://scholar.google.com/',
  'https://www.google.com/',
  'https://scholar.google.it/',
  'https://scholar.google.com/citations'
]

def random_headers
  {
    'User-Agent' => random_user_agent,
    'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language' => ['en-US,en;q=0.9,it-IT,it;q=0.8'].sample,
    'Referer' => REFERERS.sample
  }
end

def jitter_sleep(min = MIN_DELAY, max = MAX_DELAY)
  sleep_time = rand(min..max) + rand
  sleep(sleep_time)
end

def exponential_backoff_sleep(attempt)
  base = 2**attempt
  jitter = rand(0.0..1.0)
  sleep_time = [base + jitter, 300].min
  sleep(sleep_time)
end

def normalize_title(t)
  return '' if t.nil?
  s = t.dup
  s = s.gsub(/\p{Punct}/, ' ')
  s = s.gsub(/[^0-9A-Za-zÀ-ž\s]/, ' ')
  s = s.downcase.strip
  s.gsub(/\s+/, ' ')
end

def canonical_words(t)
  normalize_title(t).split.reject { |w| w.length <= 2 }
end

JW = FuzzyStringMatch::JaroWinkler.create(:native)
def fuzzy_sim(a, b)
  JW.getDistance(a, b)
end

# === READ/WRITE BIB ===
def read_existing_titles(bibfile)
  return [] unless File.exist?(bibfile)
  content = File.read(bibfile, encoding: 'UTF-8')
  titles = []
  content.scan(/(?<!\w)title\s*=\s*\{([^}]+)\}/i) { |m| titles << normalize_title(m.first) }
  titles.uniq
rescue => e
  warn "Error reading #{bibfile}: #{e.class} - #{e.message}"
  []
end

def backup_bib(bibfile)
  FileUtils.mkdir_p(BACKUP_DIR)
  ts = Time.now.utc.iso8601.gsub(':','-')
  dest = File.join(BACKUP_DIR, "bibliography_#{ts}.bib")
  FileUtils.cp(bibfile, dest)
  dest
end

# === SCHOLAR SCRAPING ===
def agent_setup
  a = Mechanize.new
  a.user_agent = random_user_agent
  a.keep_alive = false
  a.open_timeout = 30
  a.read_timeout = 60
  a.max_history = 0
  a.verify_mode = OpenSSL::SSL::VERIFY_PEER
  if PROXY_LIST.any?
    proxy = PROXY_LIST.sample
    uri = URI(proxy)
    a.set_proxy(uri.host, uri.port, uri.user, uri.password)
  end
  a
end

def fetch_scholar_titles(agent, user_id)
  titles = []
  base = "https://scholar.google.com/citations?user=#{user_id}&hl=en&cstart=%d&pagesize=100"
  start = 0
  loop do
    url = format(base, start)
    puts "→ Loading profile page: #{url}"
    page = agent.get(url, [], REFERERS.sample, random_headers)
    node_titles = page.search('.gsc_a_tr .gsc_a_at').map(&:text)
    break if node_titles.empty?
    titles.concat(node_titles)
    start += 100
    jitter_sleep(1, 3)
    break if start > 1000
  rescue Mechanize::ResponseCodeError => e
    warn "HTTP error fetching profile page (#{e})"
    break
  rescue => e
    warn "Error fetching profile page: #{e}"
    break
  end
  titles.map { |t| normalize_title(t) }.uniq
end

def title_present?(normalized_title, existing_norm_titles)
  cw = canonical_words(normalized_title)
  return true if existing_norm_titles.any? { |et| et.include?(normalized_title) || normalized_title.include?(et) }

  existing_norm_titles.each do |et|
    et_words = canonical_words(et)
    next if et_words.empty? || cw.empty?
    inter = (et_words & cw).size
    union = (et_words | cw).size
    ratio = inter.to_f / [union,1].max
    return true if ratio > 0.75
  end

  existing_norm_titles.each do |et|
    sim = fuzzy_sim(normalized_title, et)
    return true if sim >= 0.87
  end

  false
end

def generate_bib_from_row(tr)
  link_el = tr.at_css('.gsc_a_t a')
  title = link_el&.text.to_s.strip
  href  = link_el&.[]('href')
  url = href ? URI.join("https://scholar.google.com", href).to_s : ''

  authors_raw = tr.at_css('.gsc_a_t .gs_gray:nth-of-type(1)')&.text.to_s.strip
  venue_raw = tr.at_css('.gsc_a_t .gs_gray:nth-of-type(2)')&.text.to_s.strip
  year = tr.at_css('.gsc_a_y span')&.text.to_s.strip
  publisher = nil
  doi = nil
  return nil if title.empty?

  if url && !url.empty?
    pub_page = download_html(url)
    if pub_page
      body_text = pub_page.text
      doi_match = body_text.match(%r{10\.\d{4,9}/[-._;()/:A-Za-z0-9]+})
      doi = doi_match[0] if doi_match

      if body_text =~ /(Springer|Elsevier|IEEE|ACM|Wiley|MDPI|Frontiers|Taylor & Francis)/i
        publisher = $1
      end
    end
  end

  authors = authors_raw.split(/,|;/).map(&:strip).join(' and ')

  if venue_raw =~ /(.*?)(\d{1,4})/
    venue = $1.strip
    volume = $2.strip
  else
    venue = venue_raw
    volume = ""
  end

  id = "SCHOLAR_" + Digest::MD5.hexdigest("#{title}-#{authors}-#{year}")[0..7]
  type = venue =~ /conf|proceedings/i ? 'inproceedings' : 'article'

  # escape
  title_esc = title.gsub('{','\{').gsub('}','\}')
  authors_esc = authors.gsub('{','\{').gsub('}','\}')
  venue_esc = venue.gsub('{','\{').gsub('}','\}')

  bib = "@#{type}{#{id},\n" \
        "  author = {#{authors_esc}},\n" \
        "  title  = {#{title_esc}},\n" \
        "  #{type == 'article' ? 'journal' : 'booktitle'} = {#{venue_esc}},\n" \
        "  #{volume.empty? ? '' : "volume = {#{volume}},\n"}" \
        "  year = {#{year}},\n"
  bib
  bib += "  publisher = {#{publisher}},\n" if publisher
  bib += "  doi = {#{doi}},\n" if doi
  bib += "  url = {#{url}},\n" if url && !url.empty?
  bib += "}"
end

# === MAIN ===
def main
  puts "=== scholar_sync starting ==="
  unless File.exist?(BIB_FILE)
    warn "File #{BIB_FILE} not found. Exiting."
    exit 1
  end

  puts "→ Backup current bib..."
  backup_path = backup_bib(BIB_FILE)
  puts "   backup saved to #{backup_path}"

  existing = read_existing_titles(BIB_FILE)
  puts "→ #{existing.size} titles read from #{BIB_FILE}"

  agent = agent_setup
  scholar_titles = fetch_scholar_titles(agent, SCHOLAR_USER_ID)
  puts "→ #{scholar_titles.size} titles found on Scholar (normalized)."

  exclude_titles = read_exclude_titles('exclude_titles.txt')
  exclude_titles.map! { |t| normalize_title(t) }
  to_add_rows = []
  profile_url = "https://scholar.google.com/citations?user=#{SCHOLAR_USER_ID}&hl=en&view_op=list_works&pagesize=100"
  page = download_html(profile_url)
  if page
    page.css('.gsc_a_tr').each do |tr|
      norm_title = normalize_title(tr.at_css('.gsc_a_t a')&.text.to_s)
      next if exclude_titles.include?(norm_title)
      next if title_present?(norm_title, existing)
      to_add_rows << tr
    end
  end

  puts "→ #{to_add_rows.size} potential missing titles."

  if to_add_rows.empty?
    puts "No new titles to add. Exiting."
    return
  end

  File.open(BIB_FILE, 'a:UTF-8') do |f|
    to_add_rows.each_with_index do |tr, idx|
      bib_entry = generate_bib_from_row(tr)
      next unless bib_entry
      f.puts "\n\n% Added from Google Scholar on #{Time.now.utc.iso8601}"
      f.puts bib_entry
      puts "[#{idx+1}/#{to_add_rows.size}] ✓ Added: #{tr.at_css('.gsc_a_t a')&.text.to_s[0..100]}"
      jitter_sleep(1, 3)
    end
  end

  puts "\n=== scholar_sync completed ==="
end

main if __FILE__ == $0
