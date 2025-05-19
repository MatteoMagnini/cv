#!/usr/bin/env ruby
require 'nokogiri'
require 'net/http'
require 'uri'

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
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64; IP=#{ip}) " \
  "AppleWebKit/537.36 (KHTML, like Gecko) " \
  "Chrome/113.0.0.0 Safari/537.36"
end

def download_html(url)
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == 'https')

  request = Net::HTTP::Get.new(uri.request_uri)

  # User-Agent e IP random
  request['User-Agent'] = random_user_agent
  request['X-Forwarded-For'] = random_ip
  request['Client-IP'] = random_ip

  response = http.request(request)
  raise "HTTP Error #{response.code}" unless response.is_a?(Net::HTTPSuccess)
  Nokogiri::HTML(response.body)
rescue => e
  puts "Errore nel download: #{e.message}"
  nil
end

def generate_scholar_tex
  scholar_url = 'https://scholar.google.com/citations?user=iJDPEaUAAAAJ&hl=en'
  scholar_page = download_html(scholar_url)
  return false unless scholar_page

  since = scholar_page.xpath('//*[@class="gsc_rsb_sth"]')
                      .map(&:text)
                      .find { |text| text.include?('Since') }

  cited_by = scholar_page.xpath('//*[@class="gsc_rsb_std"]').map(&:text)
  return false unless cited_by.length >= 6

  tex = <<-TeX
% !TeX root = curriculum.tex
\\textbf{\\href{#{scholar_url}}{Google Scholar metrics as of #{Time.now.strftime('%Y-%m-%d')}}}
\\medskip
\\centering
\\begin{minipage}{.4\\textwidth}
    \\begin{outerlist}
        \\item[] Overall
        \\begin{innerlist}
            \\item Citations: #{cited_by[0]}
            \\item h-Index: #{cited_by[2]}
            \\item i10-Index: #{cited_by[4]}
        \\end{innerlist}
    \\end{outerlist}
\\end{minipage}
\\hfill
\\begin{minipage}{.4\\textwidth}
    \\begin{outerlist}
        \\item[] #{since}
        \\begin{innerlist}
            \\item Citations: #{cited_by[1]}
            \\item h-Index: #{cited_by[3]}
            \\item i10-Index: #{cited_by[5]}
        \\end{innerlist}
    \\end{outerlist}
\\end{minipage}
\\vspace{1em}
  TeX

  File.write('scholar.tex', tex)
  puts "✓ 'scholar.tex' creato con successo."
  true
end

# Retry loop in CI
max_attempts = 3
attempt = 1
until File.exist?('scholar.tex') || attempt > max_attempts
  puts "Tentativo #{attempt} di generazione 'scholar.tex'..."
  break if generate_scholar_tex

  attempt += 1
  sleep 30 if attempt <= max_attempts
end

unless File.exist?('scholar.tex')
  puts "✗ Fallita la generazione di 'scholar.tex' dopo #{max_attempts} tentativi."
  exit 1
end
